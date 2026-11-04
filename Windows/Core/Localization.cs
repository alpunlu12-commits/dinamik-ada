using System.Globalization;

namespace DinamikAda.Core;

public enum AppLanguage { English, Turkish }

/// <summary>
/// Seçili dil. macOS sürümündeki gibi metinler kaynak dosyasında değil kodda,
/// çiftler hâlinde duruyor: eksik çeviri derleme hatası olur, sessizce İngilizce
/// kalan bir metin olmaz.
/// </summary>
public static class Localization
{
    public static AppLanguage Language { get; set; } = AppLanguage.English;

    /// <summary>Tarih ve saatler sistemin değil seçilen dilin yerel ayarını izler.</summary>
    public static CultureInfo Culture => Language == AppLanguage.Turkish
        ? CultureInfo.GetCultureInfo("tr-TR")
        : CultureInfo.GetCultureInfo("en-US");

    /// <summary>
    /// Büyük harfe çevirme yerel ayarla yapılır: düz ToUpper "Sistem"i SISTEM
    /// yapardı, doğrusu SİSTEM.
    /// </summary>
    public static string Upper(string text) => text.ToUpper(Culture);

    public static string Label(AppLanguage l) => l == AppLanguage.Turkish ? "Türkçe" : "English";
}

/// <summary>Kullanıcının okuyabileceği her metin. T(ingilizce, türkçe) çifti tek satırda.</summary>
public static class Strings
{
    private static string T(string english, string turkish) =>
        Localization.Language == AppLanguage.Turkish ? turkish : english;

    public static string AppName => T("Dynamic Island", "Dinamik Ada");

    // MARK: Ada bölümleri

    public static string NowPlaying => T("Now Playing", "Çalıyor");
    public static string UpNext => T("Up Next", "Sırada");
    public static string Timer => T("Timer", "Zamanlayıcı");
    public static string Shelf => T("Shelf", "Raf");
    public static string System => T("System", "Sistem");

    // MARK: Ada içerikleri

    public static string NothingPlaying => T("Nothing playing", "Bir şey çalmıyor");
    public static string DynamicIsland => T("Dynamic Island", "Dinamik Ada");
    public static string PowerAdapter => T("Power Adapter", "Güç Adaptörü");
    public static string OnBattery => T("On Battery", "Pilde");
    public static string Connected => T("Connected", "Bağlandı");
    public static string TimerFinished => T("Timer finished", "Zamanlayıcı bitti");
    public static string Muted => T("Muted", "Sessiz");
    public static string Paused => T("Paused", "Duraklatıldı");
    public static string DropFilesHere => T("Drop files here", "Dosyaları buraya bırak");
    public static string ReleaseToKeep => T("Release to keep", "Bırak ve sakla");
    public static string Copy => T("Copy", "Kopyala");
    /// <summary>macOS'taki AirDrop'un karşılığı: Windows paylaşım penceresi (Yakındaki paylaşım dahil).</summary>
    public static string Share => T("Share", "Paylaş");
    public static string Clear => T("Clear", "Temizle");

    // Türkçe sayıdan sonra ismi çoğullamaz.
    public static string Files(int count) => T(count == 1 ? "1 file" : $"{count} files", $"{count} dosya");
    public static string MinutesShort(int minutes) => T($"{minutes} min", $"{minutes} dk");
    public static string MinutesLong(int minutes) => T(minutes == 1 ? "1 minute" : $"{minutes} minutes", $"{minutes} dakika");

    /// <summary>"1h 24m" / "1sa 24dk"</summary>
    public static string Duration(int hours, int minutes) => hours > 0
        ? T($"{hours}h {minutes}m", $"{hours}sa {minutes}dk")
        : T($"{minutes}m", $"{minutes}dk");

    public static string UntilFull(string duration) => T($"{duration} until full", $"dolmasına {duration}");
    public static string Remaining(string duration) => T($"{duration} remaining", $"{duration} kaldı");

    // MARK: Takvim

    public static string JustNow => T("now", "şimdi");
    public static string InMinutes(int minutes) => T($"in {minutes} min", $"{minutes} dk sonra");
    public static string InHours(string hours) => T($"in {hours} h", $"{hours} sa sonra");
    public static string NothingOnCalendar => T("Nothing on the calendar", "Takvimde bir şey yok");
    public static string UpNextMenu(string title, string time, string relative) =>
        T($"Up next · {title} — {time} ({relative})", $"Sırada · {title} — {time} ({relative})");

    // MARK: Bildirim alanı menüsü

    public static string StartTimer => T("Start Timer", "Zamanlayıcı Başlat");
    public static string PauseTimer => T("Pause Timer", "Zamanlayıcıyı Duraklat");
    public static string ResumeTimer => T("Resume Timer", "Zamanlayıcıyı Sürdür");
    public static string RestartTimer => T("Restart Timer", "Zamanlayıcıyı Yeniden Başlat");
    public static string CancelTimer => T("Cancel Timer", "Zamanlayıcıyı İptal Et");
    public static string TimerOff => T("Timer: off", "Zamanlayıcı: kapalı");
    public static string NowPlayingOff => T("Now Playing: off", "Çalan parça: kapalı");
    public static string ShelfOff => T("File shelf: off", "Dosya rafı: kapalı");
    public static string CalendarOff => T("Calendar: off", "Takvim: kapalı");
    public static string CalendarNeedsLink => T("Calendar: add an iCal link in Settings…", "Takvim: Ayarlar'a iCal bağlantısı ekle…");
    public static string CalendarFailedMenu => T("Calendar could not be read…", "Takvim okunamadı…");

    public static string TimerStatus(string time, bool running) => running
        ? T($"Timer · {time}", $"Zamanlayıcı · {time}")
        : T($"Timer · {time} (paused)", $"Zamanlayıcı · {time} (duraklatıldı)");

    public static string ShelfEmptyHint => T("Shelf empty · drag a file to the island", "Raf boş · bir dosyayı adaya sürükle");
    public static string ShelfStatus(int count) => T($"Shelf · {Files(count)}", $"Raf · {Files(count)}");
    public static string CopyShelfFiles => T("Copy Shelf Files", "Raftaki Dosyaları Kopyala");
    public static string ShareShelfFiles => T("Share Shelf Files…", "Raftaki Dosyaları Paylaş…");
    public static string ClearShelf => T("Clear Shelf", "Rafı Temizle");
    public static string DemoExpand => T("Demo: Expand Island", "Demo: Adayı Genişlet");
    public static string DemoShowCC => T("Demo: Show Control Center", "Demo: Kontrol Merkezini Göster");
    public static string DemoHideCC => T("Demo: Hide Control Center", "Demo: Kontrol Merkezini Gizle");
    public static string SettingsItem => T("Settings…", "Ayarlar…");
    public static string Quit => T("Quit Dynamic Island", "Dinamik Ada'dan Çık");

    // MARK: Ayarlar

    public static string SettingsTitle => T("Dynamic Island — Settings", "Dinamik Ada — Ayarlar");
    public static string Done => T("Done", "Bitti");
    public static string Modules => T("Modules", "Modüller");
    public static string Volume => T("Volume", "Ses");
    public static string Brightness => T("Brightness", "Parlaklık");
    public static string Battery => T("Battery", "Pil");
    public static string BluetoothDevices => T("Bluetooth devices", "Bluetooth cihazları");
    public static string CameraMicrophone => T("Camera & microphone", "Kamera ve mikrofon");
    public static string FileShelf => T("File shelf", "Dosya rafı");
    public static string Calendar => T("Calendar", "Takvim");
    public static string Granted => T("Granted", "Verildi");
    public static string Appearance => T("Appearance", "Görünüm");
    public static string Display => T("Display", "Ekran");
    public static string Automatic => T("Automatic", "Otomatik");
    public static string IslandSizeLabel => T("Island size", "Ada boyutu");
    public static string Small => T("Small", "Küçük");
    public static string Medium => T("Medium", "Orta");
    public static string AnimationSpeedLabel => T("Animation speed", "Animasyon hızı");
    public static string Slow => T("Slow", "Yavaş");
    public static string Normal => T("Normal", "Normal");
    public static string Fast => T("Fast", "Hızlı");
    public static string AutoCollapseDelay => T("Auto-collapse delay", "Otomatik toplanma gecikmesi");

    public static string AutoCollapseHint(double seconds)
    {
        var value = seconds.ToString("0.00", Localization.Culture);
        return T($"{value} s after the pointer leaves the island. Clicking anywhere else closes it at once.",
                 $"İmleç adadan ayrıldıktan {value} sn sonra. Başka bir yere tıklayınca hemen kapanır.");
    }

    public static string General => T("General", "Genel");
    public static string LanguageLabel => T("Language", "Dil");
    public static string SnapLevels => T("Snap volume to 5%", "Sesi %5'in katlarına oturt");
    public static string SoundEffects => T("Sound effects", "Ses efektleri");
    public static string LaunchAtLogin => T("Launch at sign-in", "Oturum açılınca başlat");
    public static string LaunchAtLoginFailed => T("Windows refused to register the startup entry.",
                                                  "Windows başlangıç kaydını kabul etmedi.");

    // MARK: Raf sağ tık menüsü

    public static string Open => T("Open", "Aç");
    public static string RevealInExplorer => T("Show in File Explorer", "Dosya Gezgini'nde Göster");
    public static string ShareEllipsis => T("Share…", "Paylaş…");
    public static string MoveToEllipsis => T("Move To…", "Şuraya Taşı…");
    public static string RemoveFromShelf => T("Remove from Shelf", "Raftan Kaldır");
    public static string MoveHere => T("Move Here", "Buraya Taşı");
    public static string OpenCount(int count) => T($"Open {Files(count)}", $"{Files(count)} aç");
    public static string RemoveCount(int count) => T($"Remove {Files(count)}", $"{Files(count)} kaldır");
    public static string MoveMessage(int count) => T($"Choose where to move {Files(count)}.", $"{Files(count)} nereye taşınacak, seç.");
    public static string SelectedCount(int count) => T($"{count} selected", $"{count} seçili");
    public static string MoveFailed => T("Some files could not be moved", "Bazı dosyalar taşınamadı");

    // MARK: Güç

    public static string FullyCharged => T("Fully charged", "Tam doldu");

    /// <summary>
    /// Bilerek sayısız: satır sağda gerçek yüzdeyi zaten gösteriyor; yanına eşiği
    /// yazmak ("%20" yanında büyük "%15") çelişki gibi okunur.
    /// </summary>
    public static string LowBattery => T("Low battery", "Pil azaldı");

    // MARK: İndirmeler

    public static string Downloads => T("Downloads", "İndirilenler");
    public static string DownloadFinished => T("Download finished", "İndirme bitti");
    public static string Downloading(int others) => others > 0
        ? T($"Downloading · +{others} more", $"İndiriliyor · +{others} tane daha")
        : T("Downloading…", "İndiriliyor…");

    public static string DownloadsHint => T(
        "Watches the Downloads folder and shows a file as it arrives. No percentage is shown: no browser publishes the expected size in a way another app can read, and an invented progress bar would be a guess.",
        "İndirilenler klasörünü izler ve gelen dosyayı gösterir. Yüzde gösterilmez: hiçbir tarayıcı beklenen boyutu başka bir uygulamanın okuyabileceği şekilde yayınlamaz, uydurma bir ilerleme çubuğu ise tahmin olurdu.");

    public static string DownloadsStatus(string name) => T($"Downloading · {name}", $"İndiriliyor · {name}");

    // MARK: Sistem geneli medya

    public static string SystemWideMedia => T("System-wide media", "Sistem geneli medya");
    public static string MediaActive => T("Active", "Etkin");
    public static string MediaUnavailable => T("Unavailable", "Kullanılamıyor");
    public static string MediaHint => T(
        "Now Playing is read from Windows' own media sessions — the same source as the media flyout — so Spotify, browsers, Media Player and anything else that registers with Windows shows up, with artwork, elapsed time and controls. No permission is needed.",
        "Çalan parça Windows'un kendi medya oturumlarından okunur — ses göstergesindeki medya kartının kaynağı. Spotify, tarayıcılar, Medya Oynatıcı ve Windows'a kaydolan her şey kapak, geçen süre ve düğmeleriyle görünür. İzin gerekmez.");

    // MARK: Ses tuşları

    public static string MediaKeys => T("Replace the Windows volume flyout", "Windows ses göstergesinin yerine geç");
    public static string MediaKeysHint => T(
        "Windows draws its own volume flyout when you press the volume keys. With this on, the island takes those keys first, applies the change itself and the system flyout does not appear. Needs no permission. Brightness keys are usually handled by the laptop's firmware and cannot be taken over, so Windows' brightness flyout stays.",
        "Ses tuşlarına basınca Windows kendi ses göstergesini çizer. Bu açıkken tuşu önce ada alır, değişikliği kendisi uygular ve sistem göstergesi çıkmaz. İzin gerektirmez. Parlaklık tuşları çoğu dizüstünde donanım tarafından işlendiği için devralınamaz; Windows'un parlaklık göstergesi görünmeye devam eder.");

    // MARK: Davranış

    public static string Behaviour => T("Behaviour", "Davranış");
    public static string HideWhenFullscreen => T("Hide in full screen", "Tam ekranda gizle");
    public static string HideWhenFullscreenHint => T(
        "The island floats over full-screen apps, which is right for a volume HUD and wrong across the top of a film. This puts it away while a full-screen app owns the display.",
        "Ada tam ekran uygulamaların üzerinde durur; bu bir ses göstergesi için doğru, bir filmin üstünde yanlış. Bu ayar, ekranı tam ekran bir uygulama kullanırken adayı kaldırır.");
    public static string HideInScreenshots => T("Hide from screenshots & recordings", "Ekran görüntüsü ve kayıtlarda gizle");
    public static string HideInScreenshotsHint => T(
        "Excludes the island from screenshots, screen recordings and shared screens. Turn it off when you want the island to appear in a screenshot.",
        "Adayı ekran görüntülerinden, ekran kayıtlarından ve paylaşılan ekranlardan çıkarır. Adanın ekran görüntüsünde görünmesini istiyorsan kapat.");

    // MARK: Ayar açıklamaları

    public static string SnapLevelsHint => T(
        "Keeps the volume on a 5% grid. With the volume flyout replaced, every key press moves exactly 5% (Shift+Alt: 1%).",
        "Sesi %5'lik ızgarada tutar. Ses göstergesinin yerine geçildiğinde her tuş basışı tam %5 hareket eder (Shift+Alt: %1).");
    public static string SoundEffectsHint => T("Plays a short system sound when a timer finishes.",
                                               "Zamanlayıcı bittiğinde kısa bir sistem sesi çalar.");
    public static string DisplayHint => T(
        "Automatic uses the main display. Windows has no notch, so the island is always drawn as a pill at the top centre.",
        "Otomatik, ana ekranı kullanır. Windows'ta notch olmadığı için ada her zaman ekranın üst ortasında bir pil olarak çizilir.");

    public static string CalendarLink => T("iCal link", "iCal bağlantısı");
    public static string CalendarHint => T(
        "Paste your calendar's secret iCal address (Google Calendar: Settings → your calendar → \"Secret address in iCal format\"; Outlook: Settings → Shared calendars → Publish → ICS). It is read every five minutes, only to show the next event on the island. Treat the link like a password.",
        "Takviminin gizli iCal adresini yapıştır (Google Takvim: Ayarlar → takvimin → \"iCal biçiminde gizli adres\"; Outlook: Ayarlar → Paylaşılan takvimler → Yayımla → ICS). Beş dakikada bir, yalnızca sıradaki etkinliği adada göstermek için okunur. Bağlantıyı bir parola gibi sakla.");
    public static string CalendarStatusNone => T("No link yet", "Henüz bağlantı yok");
    public static string CalendarStatusOk => T("Connected", "Bağlandı");
    public static string CalendarStatusFailed(string reason) => T($"Could not read: {reason}", $"Okunamadı: {reason}");
}
