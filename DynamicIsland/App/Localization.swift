//
//  Localization.swift
//  DynamicIsland
//
//  Every string the user can read, in both languages, side by side.
//
//  Not `Localizable.strings`: the app offers a language *picker* rather than
//  following the system, and the standard mechanism is built around the system's
//  choice — switching it at runtime means loading a different bundle and
//  re-reading every string anyway. Keeping the pair together in code has a
//  better property for a two-language app with no translators: a missing
//  translation is a compile error, not a string that silently stays English.
//
//  `Localization.language` is a static because the island's views are built deep
//  inside AppKit-owned machinery where threading a value through every layer
//  would cost more than it explains. Changing it re-renders everything, because
//  every surface observes AppState and AppState publishes the change.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case turkish

    var id: String { rawValue }

    /// Each language names itself in its own language, the way macOS does.
    var label: String {
        switch self {
        case .english: return "English"
        case .turkish: return "Türkçe"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english: return "en_US"
        case .turkish: return "tr_TR"
        }
    }
}

enum Localization {

    /// Kept in step with AppState.
    static var language: AppLanguage = .english

    /// Dates and times follow the chosen language rather than the system, so a
    /// user reading English doesn't get Turkish month names next to it.
    static var locale: Locale { Locale(identifier: language.localeIdentifier) }

    fileprivate static func pick(_ english: String, _ turkish: String) -> String {
        language == .turkish ? turkish : english
    }
}

/// Every user-visible string. `t(english, turkish)` keeps the pair on one line.
enum Strings {

    private static func t(_ english: String, _ turkish: String) -> String {
        Localization.pick(english, turkish)
    }

    // MARK: Island sections

    static var nowPlaying: String    { t("Now Playing", "Çalıyor") }
    static var upNext: String        { t("Up Next", "Sırada") }
    static var timer: String         { t("Timer", "Zamanlayıcı") }
    static var shelf: String         { t("Shelf", "Raf") }
    static var system: String        { t("System", "Sistem") }

    // MARK: Island payloads

    static var nothingPlaying: String { t("Nothing playing", "Bir şey çalmıyor") }
    static var dynamicIsland: String  { t("Dynamic Island", "Dynamic Island") }
    static var powerAdapter: String   { t("Power Adapter", "Güç Adaptörü") }
    static var onBattery: String      { t("On Battery", "Pilde") }
    static var connected: String      { t("Connected", "Bağlandı") }
    static var timerFinished: String  { t("Timer finished", "Zamanlayıcı bitti") }
    static var muted: String          { t("Muted", "Sessiz") }
    static var paused: String         { t("Paused", "Duraklatıldı") }
    static var dropFilesHere: String  { t("Drop files here", "Dosyaları buraya bırak") }
    static var releaseToKeep: String  { t("Release to keep", "Bırak ve sakla") }
    static var copy: String           { t("Copy", "Kopyala") }
    static var airDrop: String        { t("AirDrop", "AirDrop") }
    static var clear: String          { t("Clear", "Temizle") }

    static func files(_ count: Int) -> String {
        // Turkish doesn't inflect the noun after a number.
        t(count == 1 ? "1 file" : "\(count) files", "\(count) dosya")
    }

    static func minutesShort(_ minutes: Int) -> String {
        t("\(minutes) min", "\(minutes) dk")
    }

    static func minutesLong(_ minutes: Int) -> String {
        t(minutes == 1 ? "1 minute" : "\(minutes) minutes", "\(minutes) dakika")
    }

    /// "1h 24m" / "1sa 24dk"
    static func duration(hours: Int, minutes: Int) -> String {
        hours > 0
            ? t("\(hours)h \(minutes)m", "\(hours)sa \(minutes)dk")
            : t("\(minutes)m", "\(minutes)dk")
    }

    static func untilFull(_ duration: String) -> String {
        t("\(duration) until full", "dolmasına \(duration)")
    }

    static func remaining(_ duration: String) -> String {
        t("\(duration) remaining", "\(duration) kaldı")
    }

    // MARK: Calendar

    static var justNow: String { t("now", "şimdi") }

    static func inMinutes(_ minutes: Int) -> String {
        t("in \(minutes) min", "\(minutes) dk sonra")
    }

    static func inHours(_ hours: String) -> String {
        t("in \(hours) h", "\(hours) sa sonra")
    }

    static var nothingOnCalendar: String { t("Nothing on the calendar", "Takvimde bir şey yok") }

    static func upNextMenu(title: String, time: String, relative: String) -> String {
        t("Up next · \(title) — \(time) (\(relative))",
          "Sırada · \(title) — \(time) (\(relative))")
    }

    // MARK: Menu bar

    static var startTimer: String    { t("Start Timer", "Zamanlayıcı Başlat") }
    static var pauseTimer: String    { t("Pause Timer", "Zamanlayıcıyı Duraklat") }
    static var resumeTimer: String   { t("Resume Timer", "Zamanlayıcıyı Sürdür") }
    static var restartTimer: String  { t("Restart Timer", "Zamanlayıcıyı Yeniden Başlat") }
    static var cancelTimer: String   { t("Cancel Timer", "Zamanlayıcıyı İptal Et") }
    static var timerOff: String      { t("Timer: off", "Zamanlayıcı: kapalı") }
    static var nowPlayingOff: String { t("Now Playing: off", "Çalan parça: kapalı") }
    static var shelfOff: String      { t("File shelf: off", "Dosya rafı: kapalı") }
    static var calendarOff: String   { t("Calendar: off", "Takvim: kapalı") }

    static func timerStatus(_ time: String, running: Bool) -> String {
        running
            ? t("Timer · \(time)", "Zamanlayıcı · \(time)")
            : t("Timer · \(time) (paused)", "Zamanlayıcı · \(time) (duraklatıldı)")
    }

    static var automationNeeded: String {
        t("Artwork & controls need Automation…", "Kapak ve denetimler için Otomasyon gerekli…")
    }

    static var automationDeniedMenu: String {
        t("Nothing playing · Automation denied…", "Bir şey çalmıyor · Otomasyon reddedildi…")
    }

    static var calendarDeniedMenu: String {
        t("Calendar access denied…", "Takvim erişimi reddedildi…")
    }

    static var shelfEmptyHint: String {
        t("Shelf empty · drag a file to the notch", "Raf boş · bir dosyayı notch'a sürükle")
    }

    static func shelfStatus(_ count: Int) -> String {
        t("Shelf · \(files(count))", "Raf · \(files(count))")
    }

    static var copyShelfFiles: String    { t("Copy Shelf Files", "Raftaki Dosyaları Kopyala") }
    static var airDropShelfFiles: String { t("AirDrop Shelf Files…", "Raftaki Dosyaları AirDrop'la…") }
    static var clearShelf: String        { t("Clear Shelf", "Rafı Temizle") }
    static var demoExpand: String        { t("Demo: Expand Island", "Demo: Adayı Genişlet") }
    static var demoShowCC: String        { t("Demo: Show Control Center", "Demo: Kontrol Merkezini Göster") }
    static var demoHideCC: String        { t("Demo: Hide Control Center", "Demo: Kontrol Merkezini Gizle") }
    static var settingsItem: String      { t("Settings…", "Ayarlar…") }
    static var quit: String              { t("Quit Dynamic Island", "Dynamic Island'dan Çık") }

    // MARK: Settings

    static var modules: String       { t("Modules", "Modüller") }
    static var volume: String        { t("Volume", "Ses") }
    static var brightness: String    { t("Brightness", "Parlaklık") }
    static var battery: String       { t("Battery", "Pil") }
    static var bluetoothDevices: String { t("Bluetooth devices", "Bluetooth cihazları") }
    static var cameraMicrophone: String { t("Camera & microphone", "Kamera ve mikrofon") }
    static var fileShelf: String     { t("File shelf", "Dosya rafı") }
    static var calendar: String      { t("Calendar", "Takvim") }
    static var calendarAccess: String { t("Calendar access", "Takvim erişimi") }
    static var allow: String         { t("Allow…", "İzin ver…") }
    static var openSettings: String  { t("Open Settings…", "Ayarları Aç…") }
    static var automation: String    { t("Automation", "Otomasyon") }
    static var granted: String       { t("Granted", "Verildi") }
    static var denied: String        { t("Denied", "Reddedildi") }
    static var notRequested: String  { t("Not requested yet", "Henüz istenmedi") }
    static var noPlayerRunning: String { t("No player running", "Oynatıcı çalışmıyor") }

    static var appearance: String    { t("Appearance", "Görünüm") }
    static var display: String       { t("Display", "Ekran") }
    static var automatic: String     { t("Automatic", "Otomatik") }
    static var builtIn: String       { t("Built-in", "Dahili") }
    static var notch: String         { t("Notch", "Notch") }
    static var noNotch: String       { t("None — using a simulated pill", "Yok — simüle pil kullanılıyor") }

    static func notchDetected(width: Int, height: Int) -> String {
        t("Detected · \(width) × \(height) pt", "Algılandı · \(width) × \(height) pt")
    }

    static var islandSize: String     { t("Island size", "Ada boyutu") }
    static var small: String          { t("Small", "Küçük") }
    static var medium: String         { t("Medium", "Orta") }
    static var animationSpeed: String { t("Animation speed", "Animasyon hızı") }
    static var slow: String           { t("Slow", "Yavaş") }
    static var normal: String         { t("Normal", "Normal") }
    static var fast: String           { t("Fast", "Hızlı") }
    static var autoCollapseDelay: String { t("Auto-collapse delay", "Otomatik toplanma gecikmesi") }

    static func autoCollapseHint(_ seconds: Double) -> String {
        let value = String(format: "%.2f", seconds)
        return t("\(value) s after the pointer leaves the island. Clicking anywhere else closes it at once.",
                 "İmleç adadan ayrıldıktan \(value) sn sonra. Başka bir yere tıklayınca hemen kapanır.")
    }

    static var general: String       { t("General", "Genel") }
    static var language: String      { t("Language", "Dil") }
    static var snapLevels: String    { t("Snap volume & brightness to 5%", "Ses ve parlaklığı %5'in katlarına oturt") }
    static var soundEffects: String  { t("Sound effects", "Ses efektleri") }
    static var launchAtLogin: String { t("Launch at login", "Girişte başlat") }

    // MARK: Notifications

    static var notifications: String { t("Notifications", "Bildirimler") }
    static var accessibility: String { t("Accessibility", "Erişilebilirlik") }
    static var notGranted: String    { t("Not granted", "Verilmedi") }
    static var notificationsOff: String { t("Notifications: off", "Bildirimler: kapalı") }
    static var notificationsOn: String  { t("Notifications: on", "Bildirimler: açık") }

    static var notificationsNeedAccessibility: String {
        t("Notifications need Accessibility…", "Bildirimler için Erişilebilirlik gerekli…")
    }

    static func lastBanner(_ text: String) -> String {
        t("Last banner read: \(text)", "Son okunan bildirim: \(text)")
    }

    static var notificationsHint: String {
        t("macOS has no supported way to read another app's notifications. The island reads the banner as it is drawn, which needs Accessibility. Nothing is stored: the text is shown and dropped. Granting this to a copy running from a build folder stops working after each rebuild.",
          "macOS'ta başka bir uygulamanın bildirimlerini okumanın desteklenen bir yolu yok. Ada bildirimi ekrana çizildiği hâliyle okur, bunun için Erişilebilirlik gerekir. Hiçbir şey saklanmaz: metin gösterilir ve atılır. Bu izni build klasöründen çalışan bir kopyaya verirsen her yeniden derlemede geçersiz olur.")
    }

    // MARK: Shelf context menu

    static var open: String            { t("Open", "Aç") }
    static var revealInFinder: String  { t("Reveal in Finder", "Finder'da Göster") }
    static var airDropEllipsis: String { t("AirDrop…", "AirDrop…") }
    static var moveToEllipsis: String  { t("Move To…", "Şuraya Taşı…") }
    static var removeFromShelf: String { t("Remove from Shelf", "Raftan Kaldır") }
    static var moveHere: String        { t("Move Here", "Buraya Taşı") }

    static func openCount(_ count: Int) -> String {
        t("Open \(files(count))", "\(files(count)) aç")
    }

    static func removeCount(_ count: Int) -> String {
        t("Remove \(files(count))", "\(files(count)) kaldır")
    }

    static func moveMessage(_ count: Int) -> String {
        t("Choose where to move \(files(count)).",
          "\(files(count)) nereye taşınacak, seç.")
    }

    static func selectedCount(_ count: Int) -> String {
        t("\(count) selected", "\(count) seçili")
    }

    // MARK: Power

    static var fullyCharged: String { t("Fully charged", "Tam doldu") }

    /// Deliberately without a number: the row already shows the real percentage
    /// on the right, and printing the *threshold* next to it ("Low battery ·
    /// 20%" beside a big "15%") reads as a contradiction.
    static var lowBattery: String { t("Low battery", "Pil azaldı") }

    // MARK: Downloads

    static var downloads: String { t("Downloads", "İndirilenler") }
    static var downloadFinished: String { t("Download finished", "İndirme bitti") }

    static func downloading(others: Int) -> String {
        others > 0
            ? t("Downloading · +\(others) more", "İndiriliyor · +\(others) tane daha")
            : t("Downloading…", "İndiriliyor…")
    }

    static var downloadsHint: String {
        t("Watches the Downloads folder and shows a file as it arrives. No percentage is shown: no browser publishes the expected size in a way another app can read, and an invented progress bar would be a guess.",
          "İndirilenler klasörünü izler ve gelen dosyayı gösterir. Yüzde gösterilmez: hiçbir tarayıcı beklenen boyutu başka bir uygulamanın okuyabileceği şekilde yayınlamaz, uydurma bir ilerleme çubuğu ise tahmin olurdu.")
    }

    static func downloadsStatus(_ name: String) -> String {
        t("Downloading · \(name)", "İndiriliyor · \(name)")
    }

    // MARK: MediaRemote

    static var systemWideMedia: String { t("System-wide media", "Sistem geneli medya") }
    static var mediaRemoteActive: String { t("Active", "Etkin") }
    static var mediaRemoteIdle: String { t("Installed, waiting", "Kurulu, bekliyor") }
    static var mediaRemoteMissing: String { t("Not installed", "Kurulu değil") }

    static var mediaRemoteHintActive: String {
        t("Now Playing is read from the system-wide record, so it covers browsers, VLC and anything else that plays audio — and needs no permission at all. Elapsed time and the scrubber come from here too.",
          "Çalan parça, sistem genelindeki kayıttan okunuyor; yani tarayıcılar, VLC ve ses çalan her şey görünür — üstelik hiçbir izin gerekmez. Geçen süre ve sürgü de buradan gelir.")
    }

    static var mediaRemoteHintMissing: String {
        t("The mediaremote-adapter files are not in this build, so Now Playing sees only Music and Spotify. Building and dropping them into DynamicIsland/Vendor adds browser media, elapsed time and the scrubber — see that folder's README.",
          "mediaremote-adapter dosyaları bu derlemede yok, bu yüzden çalan parça yalnızca Music ve Spotify'ı görüyor. Derleyip DynamicIsland/Vendor içine koymak tarayıcı medyasını, geçen süreyi ve sürgüyü ekler — o klasördeki README'ye bak.")
    }

    // MARK: Media keys

    static var mediaKeys: String {
        t("Replace the system HUD", "Sistem HUD'unu değiştir")
    }

    static var mediaKeysHint: String {
        t("macOS draws its own volume and brightness HUD, and offers no way to turn it off. The island can only replace it by taking the key press first, which needs Accessibility. Keys it cannot apply — keyboard backlight, or a module you have switched off — are passed straight through to the system.",
          "macOS kendi ses ve parlaklık HUD'unu çizer ve bunu kapatmanın bir yolunu sunmaz. Ada bunun yerine geçebilmek için tuşa önce kendisi bakmalı, bu da Erişilebilirlik gerektirir. Uygulayamadığı tuşlar — klavye aydınlatması ya da kapattığın bir modül — doğrudan sisteme geçirilir.")
    }

    static var mediaKeysNeedAccessibility: String {
        t("System HUD replacement needs Accessibility…",
          "Sistem HUD'unu değiştirmek için Erişilebilirlik gerekli…")
    }

    // MARK: Behaviour

    static var behaviour: String { t("Behaviour", "Davranış") }

    static var hideWhenFullscreen: String {
        t("Hide in full screen", "Tam ekranda gizle")
    }

    static var hideWhenFullscreenHint: String {
        t("The island floats over full-screen apps, which is right for a volume HUD and wrong across the top of a film. This puts it away while a full-screen app owns the display.",
          "Ada tam ekran uygulamaların üzerinde durur; bu bir ses HUD'u için doğru, bir filmin üstünde yanlış. Bu ayar, ekranı tam ekran bir uygulama kullanırken adayı kaldırır.")
    }

    static var hideInScreenshots: String {
        t("Hide from screenshots & recordings", "Ekran görüntüsü ve kayıtlarda gizle")
    }

    static var hideInScreenshotsHint: String {
        t("Excludes the island from screenshots, screen recordings and shared screens — the same switch a password field uses. Turn it off when you want the island to appear in a screenshot.",
          "Adayı ekran görüntülerinden, ekran kayıtlarından ve paylaşılan ekranlardan çıkarır — parola alanlarının kullandığı anahtarın aynısı. Adanın ekran görüntüsünde görünmesini istiyorsan kapat.")
    }

    // MARK: Settings explanations

    static var snapLevelsHint: String {
        t("macOS moves both in sixteenths, so the island would count 6, 13, 19, 25… This keeps the level on a 5% grid, and every key press then moves exactly 5%.",
          "macOS ikisini de on altıda birlik adımlarla hareket ettirir, yani ada 6, 13, 19, 25… sayardı. Bu ayar seviyeyi %5'lik ızgaraya oturtur ve her tuş basışı tam %5 hareket eder.")
    }

    static var soundEffectsHint: String {
        t("Plays a short system alert when a timer finishes.",
          "Zamanlayıcı bittiğinde kısa bir sistem sesi çalar.")
    }

    static var displayHint: String {
        t("Automatic picks the built-in notched display, and falls back to the main one. A display without a notch gets the simulated pill.",
          "Otomatik, varsa dahili notch'lu ekranı seçer, yoksa ana ekrana döner. Notch'u olmayan bir ekranda simüle pil çizilir.")
    }

    static var calendarHint: String {
        t("Reads only the next event, and only to show it on the island. Nothing is sent anywhere.",
          "Yalnızca sıradaki etkinliği, yalnızca adada göstermek için okur. Hiçbir şey dışarı gönderilmez.")
    }

    static var automationHintDenied: String {
        t("Track detection still works without it — it does not use Automation. Album artwork and the play/skip buttons do, so those stay unavailable until you allow Dynamic Island to control Music and Spotify.",
          "Parça algılama bunsuz da çalışır — Otomasyon kullanmaz. Albüm kapağı ve oynat/atla düğmeleri kullanır; Dynamic Island'ın Music ve Spotify'ı kontrol etmesine izin verene kadar bunlar çalışmaz.")
    }

    static var automationHint: String {
        t("Track and play state are read from the system-wide notifications Music and Spotify broadcast, which need no permission. Automation is only used for album artwork and the transport buttons. Browser media is not reachable either way.",
          "Parça ve çalma durumu, Music ve Spotify'ın sistem geneline yayınladığı bildirimlerden okunur; bunun için izin gerekmez. Otomasyon yalnızca albüm kapağı ve oynatma düğmeleri için kullanılır. Tarayıcı medyasına her iki durumda da erişilemez.")
    }
}
