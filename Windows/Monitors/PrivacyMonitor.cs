using System;
using System.Windows.Threading;
using DinamikAda.Island;
using Microsoft.Win32;

namespace DinamikAda.Monitors;

/// <summary>
/// Kamera ya da mikrofon şu an bir şey tarafından kullanılıyor mu.
///
/// Windows, Gizlilik ayarlarındaki "son erişim" listesini kayıt defterinde
/// tutar (CapabilityAccessManager\ConsentStore). Bir uygulama aygıtı kullanırken
/// LastUsedTimeStop değeri 0'dır. Hiçbir akış açılmaz, dolayısıyla kamera ya da
/// mikrofon izni istenmez: uygulama neyin kaydedildiğini değil, yalnızca kayıt
/// olduğu bilgisini okur. Windows'un kendi göstergesi hâlâ asıl kaynaktır.
/// </summary>
public sealed class PrivacyMonitor
{
    public Action<PrivacyState>? OnChange { get; set; }
    public PrivacyState State { get; private set; } = PrivacyState.Idle;

    private const string Root = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\";
    private DispatcherTimer? _timer;

    public void Start()
    {
        if (_timer != null) return;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) => Poll();
        _timer.Start();
        Poll();
    }

    public void Stop()
    {
        _timer?.Stop();
        _timer = null;
        State = PrivacyState.Idle;
    }

    private void Poll()
    {
        var fresh = new PrivacyState(InUse("webcam"), InUse("microphone"));
        if (fresh == State) return;
        State = fresh;
        OnChange?.Invoke(fresh);
    }

    private static bool InUse(string capability)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(Root + capability);
            return key != null && AnyActive(key);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>Paketli uygulamalar doğrudan, masaüstü uygulamaları "NonPackaged" altında.</summary>
    private static bool AnyActive(RegistryKey key)
    {
        foreach (var name in key.GetSubKeyNames())
        {
            using var sub = key.OpenSubKey(name);
            if (sub == null) continue;
            if (name == "NonPackaged")
            {
                if (AnyActive(sub)) return true;
                continue;
            }
            if (sub.GetValue("LastUsedTimeStop") is long stop && stop == 0
                && sub.GetValue("LastUsedTimeStart") is long start && start != 0) return true;
        }
        return false;
    }
}
