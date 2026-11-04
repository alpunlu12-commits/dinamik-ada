using System;
using System.Text;
using System.Windows.Threading;

namespace DinamikAda.Monitors;

/// <summary>
/// Adanın ekranını tam ekran bir uygulama kullanıyor mu. Algılama izinsizdir:
/// ön plandaki pencerenin dikdörtgeni ekranı tümüyle kaplıyor mu, ya da Windows
/// "tam ekran Direct3D / sunum" diyor mu. Ön plan değişimi dinlenir; zaten önde
/// olan bir videonun tam ekrana geçmesi bunu üretmediği için 1 Hz emniyet
/// yoklaması da var.
/// </summary>
public sealed class FullscreenDetector
{
    public Action<bool>? OnChange { get; set; }
    /// <summary>Adanın bulunduğu ekran (monitör tanıtıcısı).</summary>
    public IntPtr Monitor { get; set; }
    /// <summary>Kendi penceremiz; onu tam ekran saymayalım.</summary>
    public IntPtr Own { get; set; }

    private DispatcherTimer? _timer;
    private IntPtr _hook;
    private readonly Native.WinEventProc _proc;
    private bool _last;

    public FullscreenDetector() => _proc = (_, _, _, _, _, _, _) => Check();

    public void Start()
    {
        if (_timer != null) return;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) => Check();
        _timer.Start();
        _hook = Native.SetWinEventHook(Native.EVENT_SYSTEM_FOREGROUND, Native.EVENT_SYSTEM_FOREGROUND, IntPtr.Zero, _proc, 0, 0, Native.WINEVENT_OUTOFCONTEXT);
        Check();
    }

    public void Stop()
    {
        _timer?.Stop();
        _timer = null;
        if (_hook != IntPtr.Zero) { Native.UnhookWinEvent(_hook); _hook = IntPtr.Zero; }
        if (_last) { _last = false; OnChange?.Invoke(false); }
    }

    private void Check()
    {
        var now = IsFullscreen();
        if (now == _last) return;
        _last = now;
        OnChange?.Invoke(now);
    }

    private bool IsFullscreen()
    {
        var fg = Native.GetForegroundWindow();
        if (fg == IntPtr.Zero || fg == Own || fg == Native.GetShellWindow() || fg == Native.GetDesktopWindow()) return false;
        var cls = new StringBuilder(64);
        Native.GetClassName(fg, cls, cls.Capacity);
        var name = cls.ToString();
        // Masaüstü ve görev çubuğu ekranı kaplar ama tam ekran uygulama değildir.
        if (name is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd") return false;

        var monitor = Native.MonitorFromWindow(fg, Native.MONITOR_DEFAULTTONEAREST);
        if (Monitor != IntPtr.Zero && monitor != Monitor) return false;

        if (Native.SHQueryUserNotificationState(out var state) == 0
            && state is Native.QUERY_USER_NOTIFICATION_STATE.RunningD3DFullScreen or Native.QUERY_USER_NOTIFICATION_STATE.PresentationMode)
            return true;

        var info = new Native.MONITORINFOEX { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.MONITORINFOEX>() };
        if (!Native.GetMonitorInfo(monitor, ref info) || !Native.GetWindowRect(fg, out var r)) return false;
        var m = info.rcMonitor;
        return r.Left <= m.Left && r.Top <= m.Top && r.Right >= m.Right && r.Bottom >= m.Bottom;
    }
}
