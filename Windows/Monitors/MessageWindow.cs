using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace DinamikAda.Monitors;

/// <summary>
/// Güç bildirimlerini alan görünmez pencere (WM_POWERBROADCAST) — macOS'taki
/// IOKit güç kaynağı bildiriminin karşılığı. Yalnızca arayüz iş parçacığından.
/// </summary>
internal sealed class MessageWindow
{
    private static MessageWindow? _shared;
    public static MessageWindow Shared => _shared ??= new MessageWindow();

    private readonly HwndSource _source;
    private readonly Dictionary<Guid, IntPtr> _registrations = new();

    /// <summary>Güç ayarı değişti: (ayar, veri).</summary>
    public event Action<Guid, uint>? PowerSettingChanged;
    /// <summary>Sistem uykudan uyandı.</summary>
    public event Action? Resumed;

    public IntPtr Handle => _source.Handle;

    private MessageWindow()
    {
        _source = new HwndSource(new HwndSourceParameters("DinamikAdaMessages")
        {
            Width = 0, Height = 0, WindowStyle = 0, ExtendedWindowStyle = 0x80,
        });
        _source.AddHook(WndProc);
    }

    public void Subscribe(Guid setting)
    {
        if (_registrations.ContainsKey(setting)) return;
        var g = setting;
        var h = Native.RegisterPowerSettingNotification(Handle, ref g, 0);
        if (h != IntPtr.Zero) _registrations[setting] = h;
    }

    public void Unsubscribe(Guid setting)
    {
        if (_registrations.Remove(setting, out var h)) Native.UnregisterPowerSettingNotification(h);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg != Native.WM_POWERBROADCAST) return IntPtr.Zero;
        switch (wParam.ToInt32())
        {
            case Native.PBT_POWERSETTINGCHANGE when lParam != IntPtr.Zero:
                var s = Marshal.PtrToStructure<Native.POWERBROADCAST_SETTING>(lParam);
                PowerSettingChanged?.Invoke(s.PowerSetting, s.Data);
                break;
            case Native.PBT_APMRESUMEAUTOMATIC:
            case Native.PBT_APMRESUMESUSPEND:
                Resumed?.Invoke();
                break;
        }
        return IntPtr.Zero;
    }
}
