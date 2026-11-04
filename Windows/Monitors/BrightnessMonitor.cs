using System;
using System.Linq;
using System.Management;
using System.Threading.Tasks;
using System.Windows;

namespace DinamikAda.Monitors;

/// <summary>
/// Dahili ekran parlaklığı, WMI üzerinden (WmiMonitorBrightness). macOS
/// sürümü özel bir API'yi saniyede dört kez yokluyordu; Windows değişimi
/// olayla bildiriyor (WmiMonitorBrightnessEvent), yoklama yok.
///
/// Harici monitörler bu arayüzü desteklemez; o durumda modül sessizce gizlenir.
/// WMI çağrıları onlarca milisaniye sürebildiği için arayüz iş parçacığında yapılmaz.
/// </summary>
public sealed class BrightnessMonitor
{
    /// <summary>(düzey, kullanıcı mı değiştirdi)</summary>
    public Action<double, bool>? OnChange { get; set; }

    /// <summary>
    /// Uyarlamalı parlaklık sürekli minik oynatır; bunlar ada açılması için
    /// sebep değil. Yalnızca tek olayda bu eşiği aşan sıçramalar gösterge açar.
    /// </summary>
    private const double UserInitiatedThreshold = 0.015;

    private ManagementEventWatcher? _watcher;
    private double? _last;
    private bool _running;

    // Sürüklerken her olayda WMI'ya yazmak yerine son değeri tek işçiye bırak.
    private readonly object _writeLock = new();
    private double? _pendingWrite;
    private bool _writerBusy;

    public double? Current => _last;

    /// <summary>Başlatır; okunan ilk değeri (ya da desteklenmiyorsa null) geri çağrıyla verir.</summary>
    public void Start(Action<double?> initial)
    {
        if (_running) { initial(_last); return; }
        _running = true;
        Task.Run(() =>
        {
            var level = Read();
            ManagementEventWatcher? watcher = null;
            if (level != null)
            {
                try
                {
                    watcher = new ManagementEventWatcher(new ManagementScope(@"root\WMI"),
                        new EventQuery("SELECT * FROM WmiMonitorBrightnessEvent"));
                    watcher.EventArrived += OnEvent;
                    watcher.Start();
                }
                catch
                {
                    watcher = null;
                }
            }
            Application.Current?.Dispatcher.BeginInvoke(() =>
            {
                if (!_running) { watcher?.Stop(); watcher?.Dispose(); return; }
                _watcher = watcher;
                _last = level;
                initial(level);
            });
        });
    }

    public void Stop()
    {
        _running = false;
        var w = _watcher;
        _watcher = null;
        _last = null;
        if (w != null)
        {
            Task.Run(() =>
            {
                try { w.EventArrived -= OnEvent; w.Stop(); } catch { }
                w.Dispose();
            });
        }
    }

    private void OnEvent(object sender, EventArrivedEventArgs e)
    {
        double level;
        try { level = Convert.ToDouble(e.NewEvent["Brightness"]) / 100.0; }
        catch { return; }
        Application.Current?.Dispatcher.BeginInvoke(() =>
        {
            if (!_running) return;
            var previous = _last;
            _last = level;
            if (previous is { } p && Math.Abs(p - level) < 0.0005) return;
            var userInitiated = previous is { } q && Math.Abs(q - level) >= UserInitiatedThreshold;
            OnChange?.Invoke(level, userInitiated);
        });
    }

    /// <summary>Parlaklığı yazar (Kontrol Merkezi kutucuğu sürüklenirken).</summary>
    public void SetLevel(double level)
    {
        _last = Math.Clamp(level, 0, 1);
        lock (_writeLock)
        {
            _pendingWrite = _last;
            if (_writerBusy) return;
            _writerBusy = true;
        }
        Task.Run(() =>
        {
            while (true)
            {
                double value;
                lock (_writeLock)
                {
                    if (_pendingWrite is not { } next) { _writerBusy = false; return; }
                    value = next;
                    _pendingWrite = null;
                }
                Write(value);
            }
        });
    }

    private static double? Read()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(@"root\WMI", "SELECT CurrentBrightness FROM WmiMonitorBrightness");
            using var results = searcher.Get();
            var first = results.Cast<ManagementObject>().FirstOrDefault();
            return first == null ? null : Convert.ToDouble(first["CurrentBrightness"]) / 100.0;
        }
        catch
        {
            return null;   // masaüstü bilgisayar ya da yalnızca harici monitör
        }
    }

    private static void Write(double level)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(@"root\WMI", "SELECT * FROM WmiMonitorBrightnessMethods");
            using var results = searcher.Get();
            foreach (ManagementObject mo in results)
            {
                mo.InvokeMethod("WmiSetBrightness", new object[] { (uint)1, (byte)Math.Round(level * 100) });
                mo.Dispose();
            }
        }
        catch { }
    }
}
