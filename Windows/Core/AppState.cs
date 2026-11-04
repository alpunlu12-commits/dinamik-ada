using System;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using DinamikAda.Monitors;

namespace DinamikAda.Core;

/// <summary>Adanın kapladığı alan.</summary>
public enum IslandSize { Small, Medium }

/// <summary>Genişleme/toplanma yaylarının hızı.</summary>
public enum AnimationSpeed { Slow, Normal, Fast }

/// <summary>
/// Kalıcı, gözlemlenebilir kullanıcı ayarları. %APPDATA%\DinamikAda\settings.json
/// dosyasına yazılır; Ayarlar penceresi ve canlı ada değişime anında tepki verir.
///
/// "Oturum açılınca başlat" istisna: o durum Windows'un Run anahtarında yaşar,
/// buradan okunur, kopyası tutulmaz.
/// </summary>
public sealed class AppState : ObservableObject
{
    public static AppState Shared { get; } = new();

    /// <summary>Kısa tutuldu: iki saniye adanın gitmemekte direndiği hissini veriyordu.</summary>
    public const double DefaultCollapseDelay = 0.5;

    private readonly string _path = AppPaths.File("settings.json");
    private readonly JsonObject _d;

    private AppState()
    {
        try
        {
            _d = File.Exists(_path) ? (JsonNode.Parse(File.ReadAllText(_path)) as JsonObject ?? new()) : new();
        }
        catch
        {
            _d = new();
        }

        // İlk açılışta Windows Türkçe ise Türkçe, değilse İngilizce.
        if (_d["language"] == null)
        {
            var tr = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "tr";
            _d["language"] = tr ? "turkish" : "english";
        }
        Localization.Language = Language;
        _launchAtLogin = LoginItem.IsEnabled;
    }

    // MARK: Görünüm

    public AppLanguage Language
    {
        get => Get("english") == "turkish" ? AppLanguage.Turkish : AppLanguage.English;
        set
        {
            Localization.Language = value;
            Put(value == AppLanguage.Turkish ? "turkish" : "english");
        }
    }

    /// <summary>Adanın hangi ekranda duracağı: "automatic" ya da "display:&lt;aygıt yolu&gt;".</summary>
    public string PreferredDisplay { get => Get("automatic"); set => Put(value); }

    public IslandSize IslandSize
    {
        get => Get("medium") == "small" ? IslandSize.Small : IslandSize.Medium;
        set => Put(value == IslandSize.Small ? "small" : "medium");
    }

    public AnimationSpeed AnimationSpeed
    {
        get => Get("normal") switch { "slow" => AnimationSpeed.Slow, "fast" => AnimationSpeed.Fast, _ => AnimationSpeed.Normal };
        set => Put(value switch { AnimationSpeed.Slow => "slow", AnimationSpeed.Fast => "fast", _ => "normal" });
    }

    /// <summary>İmleç adadan ayrıldıktan sonra toplanmadan önce beklenecek saniye.</summary>
    public double AutoCollapseDelay { get => Get(DefaultCollapseDelay); set => Put(Math.Clamp(value, 0, 5)); }

    // MARK: Modüller

    public bool MusicEnabled { get => Get(true); set => Put(value); }
    public bool VolumeEnabled { get => Get(true); set => Put(value); }
    public bool BrightnessEnabled { get => Get(true); set => Put(value); }
    public bool BatteryEnabled { get => Get(true); set => Put(value); }
    public bool TimerEnabled { get => Get(true); set => Put(value); }
    public bool BluetoothEnabled { get => Get(true); set => Put(value); }
    public bool PrivacyEnabled { get => Get(true); set => Put(value); }

    /// <summary>Takvim açıkça istenene kadar kapalı: söyleyecek bir şeyi olması için bağlantı ister.</summary>
    public bool CalendarEnabled { get => Get(false); set => Put(value); }

    /// <summary>
    /// Takvimin iCal (ICS) adresi. Google ve Outlook'un verdiği "gizli adres"
    /// bir paroladır: bu dosya yalnızca senin Windows kullanıcına açıktır.
    /// </summary>
    public string CalendarUrl { get => Get(""); set => Put(value.Trim()); }

    public bool DownloadsEnabled { get => Get(true); set => Put(value); }
    public bool ShelfEnabled { get => Get(true); set => Put(value); }

    /// <summary>
    /// Ses tuşlarını devral: Windows'un kendi ses göstergesi yerine ada görünsün.
    /// macOS'ta Erişilebilirlik isteyen bu iş Windows'ta izin istemez; yine de
    /// sistem davranışını değiştirdiği için kullanıcı açana kadar kapalı.
    /// </summary>
    public bool MediaKeysEnabled { get => Get(false); set => Put(value); }

    /// <summary>Sesi ve parlaklığı %5'lik ızgarada tut.</summary>
    public bool SnapLevelsToFivePercent { get => Get(true); set => Put(value); }

    // MARK: Davranış

    /// <summary>Tam ekran bir uygulama adanın ekranını kullanırken çekil.</summary>
    public bool HideWhenFullscreen { get => Get(true); set => Put(value); }

    /// <summary>Adayı ekran görüntüsü, kayıt ve paylaşılan ekrandan çıkar.</summary>
    public bool HideInScreenshots { get => Get(false); set => Put(value); }

    /// <summary>Zamanlayıcı bitince kısa bir sistem sesi.</summary>
    public bool SoundEffectsEnabled { get => Get(true); set => Put(value); }

    // MARK: Sistem

    private bool _launchAtLogin;
    private string? _launchAtLoginError;

    public bool LaunchAtLogin
    {
        get => _launchAtLogin;
        set
        {
            if (LoginItem.SetEnabled(value))
            {
                LaunchAtLoginError = null;
                Set(ref _launchAtLogin, value);
            }
            else
            {
                LaunchAtLoginError = Strings.LaunchAtLoginFailed;
                Set(ref _launchAtLogin, LoginItem.IsEnabled);
            }
        }
    }

    /// <summary>Windows kaydı reddettiyse anahtar sessizce geri dönmesin, sebebi yazsın.</summary>
    public string? LaunchAtLoginError { get => _launchAtLoginError; private set => Set(ref _launchAtLoginError, value); }

    // MARK: Türetilen

    /// <summary>Bütün ada geçişlerinin yayı: (tepki süresi, sönüm oranı).</summary>
    public (double Response, double Damping) Spring => AnimationSpeed switch
    {
        AnimationSpeed.Slow => (0.70, 0.82),
        AnimationSpeed.Fast => (0.26, 0.82),
        _ => (0.42, 0.80),
    };

    // MARK: Depo

    private static string Key(string member) => char.ToLowerInvariant(member[0]) + member[1..];

    private T Get<T>(T fallback, [CallerMemberName] string member = "")
    {
        try
        {
            if (_d[Key(member)] is JsonValue v)
            {
                if (v.TryGetValue<T>(out var value)) return value;
                if (typeof(T) == typeof(double) && v.TryGetValue<int>(out var i)) return (T)(object)(double)i;
            }
        }
        catch { }
        return fallback;
    }

    private void Put<T>(T value, [CallerMemberName] string member = "")
    {
        var key = Key(member);
        var next = JsonValue.Create(value);
        if (_d[key]?.ToJsonString() == next?.ToJsonString()) return;
        _d[key] = next;
        try
        {
            var json = _d.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            AppPaths.WriteAtomic(_path, System.Text.Encoding.UTF8.GetBytes(json));
        }
        catch { }
        OnPropertyChanged(member);
    }
}
