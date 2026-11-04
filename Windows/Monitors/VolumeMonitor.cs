using System;
using System.Windows;
using DinamikAda.Core;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;

namespace DinamikAda.Monitors;

/// <summary>
/// Varsayılan çıkış aygıtının ses düzeyi ve sessiz kipi — olay tabanlı
/// (Core Audio bildirimi), yoklama yok. Varsayılan aygıt değişince (kulaklık
/// takıldı) yeni aygıta bağlanır. Arayüz iş parçacığında oluşturulur ve
/// kullanılır; bildirim geri çağrıları yalnızca arayüze aktarılır.
/// </summary>
public sealed class VolumeMonitor : IMMNotificationClient
{
    public Action<double, bool>? OnChange { get; set; }
    public bool SnapsToFivePercent { get; set; } = true;

    private MMDeviceEnumerator? _enumerator;
    private MMDevice? _device;
    private double? _lastLevel;
    private bool? _lastMuted;
    private bool _running;

    public void Start()
    {
        if (_running) return;
        _running = true;
        try
        {
            _enumerator = new MMDeviceEnumerator();
            _enumerator.RegisterEndpointNotificationCallback(this);
        }
        catch { }
        Attach();
    }

    public void Stop()
    {
        if (!_running) return;
        _running = false;
        Detach();
        try { _enumerator?.UnregisterEndpointNotificationCallback(this); } catch { }
        _enumerator?.Dispose();
        _enumerator = null;
        _lastLevel = null;
        _lastMuted = null;
    }

    private void Attach()
    {
        Detach();
        if (_enumerator == null) return;
        try
        {
            _device = _enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            _device.AudioEndpointVolume.OnVolumeNotification += OnVolumeNotification;
        }
        catch
        {
            _device = null;   // hiç çıkış aygıtı yok
        }
        _lastLevel = ReadVolume();
        _lastMuted = ReadMute();
    }

    private void Detach()
    {
        if (_device == null) return;
        try { _device.AudioEndpointVolume.OnVolumeNotification -= OnVolumeNotification; } catch { }
        _device.Dispose();
        _device = null;
    }

    private void OnVolumeNotification(AudioVolumeNotificationData data) =>
        Application.Current?.Dispatcher.BeginInvoke(Emit);

    public double? CurrentLevel() => ReadVolume();

    public void SetLevel(double level, bool? snapping = null)
    {
        if (_device == null) return;
        var snap = snapping ?? SnapsToFivePercent;
        var value = (float)(snap ? level.SnappedToFivePercent() : level.Unit());
        try
        {
            _device.AudioEndpointVolume.MasterVolumeLevelScalar = value;
            // Sesi yukarı çekmek sessize almayı da kaldırır.
            if (level > 0 && ReadMute()) _device.AudioEndpointVolume.Mute = false;
        }
        catch { }
    }

    public void ToggleMute()
    {
        if (_device == null) return;
        try { _device.AudioEndpointVolume.Mute = !ReadMute(); } catch { }
        Emit();
    }

    /// <summary>
    /// Bir ses tuşunu kendimiz uygula (Windows ses göstergesinin yerine geçerken).
    /// Adım %5 ızgarasında 0,05; ızgara kapalıysa Windows'un kendi adımı olan 0,02.
    /// Shift+Alt dörtte bir adım atar ve ızgarayı devreden çıkarır.
    /// </summary>
    public bool Step(bool up, bool precise)
    {
        if (_device == null || ReadVolume() is not { } current) return false;
        var step = SnapsToFivePercent ? 0.05 : 0.02;
        if (precise) step = SnapsToFivePercent ? 0.0125 : 0.01;
        if (up && ReadMute()) { try { _device.AudioEndpointVolume.Mute = false; } catch { } }
        var target = (current + (up ? step : -step)).Unit();
        SetLevel(target, precise ? false : null);
        Emit();
        return true;
    }

    private double? ReadVolume()
    {
        try { return _device == null ? null : Math.Clamp(_device.AudioEndpointVolume.MasterVolumeLevelScalar, 0, 1); }
        catch { return null; }
    }

    private bool ReadMute()
    {
        try { return _device?.AudioEndpointVolume.Mute ?? false; }
        catch { return false; }
    }

    private void Emit()
    {
        if (!_running || ReadVolume() is not { } level) return;
        var muted = ReadMute();
        var levelChanged = Math.Abs((_lastLevel ?? -1) - level) > 0.0005;
        var muteChanged = muted != _lastMuted;
        if (!levelChanged && !muteChanged) return;
        var previous = _lastLevel;
        _lastLevel = level;
        _lastMuted = muted;
        OnChange?.Invoke(level, muted);

        // Izgaraya oturt; ama yalnızca bir tuş basışı büyüklüğündeki sıçramaları —
        // sesini yumuşakça kısan bir uygulamayla kavga etmeyelim.
        if (!SnapsToFivePercent || level.IsOnFivePercentGrid()
            || Math.Abs((previous ?? level) - level) < Levels.DiscreteStepThreshold) return;
        SetLevel(level.SnappedToFivePercent());
    }

    // MARK: Aygıt bildirimleri (COM iş parçacığında gelir)

    void IMMNotificationClient.OnDefaultDeviceChanged(DataFlow flow, Role role, string defaultDeviceId)
    {
        if (flow == DataFlow.Render && role == Role.Multimedia)
            Application.Current?.Dispatcher.BeginInvoke(() => { if (_running) { Attach(); Emit(); } });
    }

    void IMMNotificationClient.OnDeviceStateChanged(string deviceId, DeviceState newState) { }
    void IMMNotificationClient.OnDeviceAdded(string pwstrDeviceId) { }
    void IMMNotificationClient.OnDeviceRemoved(string deviceId) { }
    void IMMNotificationClient.OnPropertyValueChanged(string pwstrDeviceId, PropertyKey key) { }
}
