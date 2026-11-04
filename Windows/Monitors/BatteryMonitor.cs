using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Threading;
using DinamikAda.Island;

namespace DinamikAda.Monitors;

/// <summary>
/// Güç kaynağı: takıldı/çıkarıldı, tam doldu ve düşük pil (%20/%10/%5).
/// Güç bildirimleriyle (GUID_ACDC_POWER_SOURCE, kalan yüzde) olay tabanlı;
/// "tam doldu" geçişi yüzde değişmeden de olabildiği için 30 sn'lik bir
/// emniyet yoklaması da var.
/// </summary>
public sealed class BatteryMonitor
{
    public PowerSnapshot? Snapshot { get; private set; }
    public Action<PowerSnapshot, PowerEvent>? OnPowerEvent { get; set; }
    /// <summary>Olay olmasa da güncel değer (Kontrol Merkezi kutucuğu için).</summary>
    public Action<PowerSnapshot?>? OnSnapshot { get; set; }

    /// <summary>
    /// Her eşik bir deşarj boyunca bir kez konuşur; aksi hâlde eşik etrafında
    /// dalgalanan okumalar %20'yi tekrar tekrar duyururdu. Fişe takınca sıfırlanır.
    /// </summary>
    private readonly HashSet<int> _announced = new();
    private static readonly int[] Thresholds = { 20, 10, 5 };
    private DispatcherTimer? _poll;
    private bool _running;

    public void Start()
    {
        if (_running) return;
        _running = true;
        Snapshot = Read();
        MessageWindow.Shared.PowerSettingChanged += OnSetting;
        MessageWindow.Shared.Subscribe(DinamikAda.Monitors.Native.GUID_ACDC_POWER_SOURCE);
        MessageWindow.Shared.Subscribe(DinamikAda.Monitors.Native.GUID_BATTERY_PERCENTAGE_REMAINING);
        _poll = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        _poll.Tick += (_, _) => Refresh();
        _poll.Start();
    }

    public void Stop()
    {
        if (!_running) return;
        _running = false;
        MessageWindow.Shared.PowerSettingChanged -= OnSetting;
        MessageWindow.Shared.Unsubscribe(DinamikAda.Monitors.Native.GUID_ACDC_POWER_SOURCE);
        MessageWindow.Shared.Unsubscribe(DinamikAda.Monitors.Native.GUID_BATTERY_PERCENTAGE_REMAINING);
        _poll?.Stop();
        _poll = null;
        _announced.Clear();
    }

    private void OnSetting(Guid setting, uint data)
    {
        if (setting == DinamikAda.Monitors.Native.GUID_ACDC_POWER_SOURCE || setting == DinamikAda.Monitors.Native.GUID_BATTERY_PERCENTAGE_REMAINING)
            Refresh();
    }

    private void Refresh()
    {
        if (!_running || Read() is not { } fresh) return;
        var previous = Snapshot;
        Snapshot = fresh;
        if (!Equals(previous, fresh)) OnSnapshot?.Invoke(fresh);
        if (previous == null) return;

        if (previous.IsPluggedIn != fresh.IsPluggedIn)
        {
            if (!fresh.IsPluggedIn) _announced.Clear();
            OnPowerEvent?.Invoke(fresh, fresh.IsPluggedIn ? new PowerEvent.PluggedIn() : new PowerEvent.Unplugged());
            return;
        }
        if (fresh.IsPluggedIn && fresh.Percentage >= 100 && previous.IsCharging && !fresh.IsCharging)
        {
            OnPowerEvent?.Invoke(fresh, new PowerEvent.FullyCharged());
            return;
        }
        if (fresh.IsPluggedIn) return;

        // Sert bir düşüşte (%25 → %3) en acil eşik konuşur; sonra geri tırmanıp %10'u anons etmez.
        var crossed = Thresholds.Where(t => fresh.Percentage <= t).DefaultIfEmpty(-1).Min();
        if (crossed < 0 || _announced.Contains(crossed)) return;
        foreach (var t in Thresholds.Where(t => t >= crossed)) _announced.Add(t);
        OnPowerEvent?.Invoke(fresh, new PowerEvent.LowBattery(crossed));
    }

    /// <summary>Pili olmayan bir masaüstünde null: o zaman modülün söyleyecek bir şeyi yok.</summary>
    public static PowerSnapshot? Read()
    {
        if (!DinamikAda.Monitors.Native.GetSystemPowerStatus(out var s)) return null;
        if (s.BatteryFlag == 128 || s.BatteryFlag == 255 || s.BatteryLifePercent > 100) return null;

        var charging = (s.BatteryFlag & 8) != 0;
        var pluggedIn = s.ACLineStatus == 1;
        int? minutes = null;
        if (charging) minutes = MinutesToFull();
        else if (!pluggedIn && s.BatteryLifeTime > 0) minutes = s.BatteryLifeTime / 60;
        return new PowerSnapshot(s.BatteryLifePercent, charging, pluggedIn, minutes is > 0 ? minutes : null);
    }

    /// <summary>Dolmasına kalan dakika, sistem şarj hızını bildiriyorsa.</summary>
    private static int? MinutesToFull()
    {
        try
        {
            var report = Windows.Devices.Power.Battery.AggregateBattery.GetReport();
            if (report.ChargeRateInMilliwatts is not { } rate || rate <= 0) return null;
            if (report.FullChargeCapacityInMilliwattHours is not { } full || report.RemainingCapacityInMilliwattHours is not { } now) return null;
            var minutes = (full - now) / (double)rate * 60;
            return minutes > 0 ? (int)Math.Round(minutes) : null;
        }
        catch
        {
            return null;
        }
    }
}
