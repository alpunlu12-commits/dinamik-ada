# Dinamik Ada — Windows sürümü

Ekranın üst ortasına Dynamic Island tarzı etkileşimli bir ada çizen Windows 10/11 uygulaması.
macOS sürümüyle aynı üç durum, aynı ölçüler, aynı yay animasyonları ve aynı Türkçe/İngilizce arayüz.

Windows 10 (2004+) / Windows 11 · x64 ve ARM64 · C# + WPF (.NET 10)

> **Durum:** ilk Windows sürümü. Derlemesi her push'ta GitHub Actions'ta doğrulanıyor.
> Bir sorun görürsen [issue aç](https://github.com/alpunlu12-commits/dinamik-ada/issues).

| Ad | Ne zaman |
|---|---|
| **ada** | Boştaki hâli — ekranın üst kenarına yaslanan kompakt pil |
| **dinamik** | Üzerine gelince açılan tek satır |
| **dinamik ada** | Tıklayınca açılan kontrol merkezi |

Windows'ta notch yok. Ada her zaman ekranın üst ortasında, macOS sürümünün "simüle notch" modundaki
gibi bir pil olarak çizilir.

---

## Kurulum

### 1. Hazır paketi indir (en kolay)

[**Releases sayfasından**](https://github.com/alpunlu12-commits/dinamik-ada/releases/latest)
`DinamikAda-Windows-win-x64.zip` indir (Snapdragon / ARM bilgisayarlarda `win-arm64`). Zip'i aç,
`DinamikAda.exe`'yi istediğin bir klasöre koy ve çalıştır. Kurulum ya da .NET gerekmez.

İlk açılışta Windows **SmartScreen** uyarır (*"Windows bilgisayarınızı korudu"*). Uygulama kod
imzalı değil; açmak için **Ek bilgi → Yine de çalıştır**.

### 2. Kaynaktan derle

[.NET 10 SDK](https://dotnet.microsoft.com/download) gerekir:

```powershell
winget install Microsoft.DotNet.SDK.10
```

Sonra:

```powershell
git clone https://github.com/alpunlu12-commits/dinamik-ada.git
cd dinamik-ada
powershell -ExecutionPolicy Bypass -File Windows\install.ps1
```

Betik derler, `%LOCALAPPDATA%\Programs\DinamikAda` altına kurar, Başlat menüsüne kısayol ekler ve
uygulamayı açar. Yönetici yetkisi istemez. Kaldırmak için aynı komutu `-Uninstall` ile çalıştır.

Uygulama görev çubuğunda değil, **bildirim alanında** (saatin yanı) yaşar. Simgeye sol tık
Ayarlar'ı açar; sağ tık menüsünde çalan parça, zamanlayıcı, raf, takvim, demo öğeleri ve Çıkış var.

---

## Modüller — Windows'ta nasıl çalışıyor

| Modül | Windows'ta | İzin |
|---|---|---|
| **Now Playing** | Windows'un medya oturumları (GSMTC): Spotify, tarayıcılar, Medya Oynatıcı ve Windows'a kaydolan her şey. Kapak, geçen süre, sürgü ve düğmeler | yok |
| **Ses** | Core Audio bildirimi (olay tabanlı); kulaklık takılınca yeni aygıta geçer | yok |
| **Parlaklık** | WMI (`WmiMonitorBrightness`), olay tabanlı | yok |
| **Pil / Güç** | Güç bildirimleri; takıldı/çıkarıldı, tam doldu, %20/%10/%5 | yok |
| **Zamanlayıcı** | Saatten türetilen geri sayım | yok |
| **Bluetooth pili** | Eşleşmiş cihazları izleyen DeviceWatcher + Windows'un Bluetooth sayfasındaki pil özelliği | yok |
| **Kamera / mikrofon** | Gizlilik ayarlarının "son erişim" kaydı (kayıt defteri); akış açılmaz | yok |
| **Dosya rafı** | Sürükle-bırak, çoklu seçim, sağ tık menüsü, dışarı sürükleme | yok |
| **İndirmeler** | İndirilenler klasörü (`.crdownload`, `.part`…), yalnız büyüyen dosyalar sayılır | yok |
| **Takvim** | iCal (ICS) bağlantısı, tekrarlayan etkinlikler dahil | bağlantı |
| **Ses tuşlarını devralma** | Düşük seviyeli klavye kancası; Windows'un ses göstergesi çıkmaz | yok |
| **Tam ekranda gizlen** | Ön plandaki pencere ekranı kaplıyor mu / tam ekran Direct3D | yok |
| **Ekran görüntüsünden gizle** | `WDA_EXCLUDEFROMCAPTURE` | yok |

### Takvim nasıl bağlanır

Windows Takvimi, paketlenmemiş (Mağaza dışı) uygulamalara kapalı. Bunun yerine takviminin gizli
iCal adresini Ayarlar → Modüller → Takvim'e yapıştırırsın:

- **Google Takvim:** Ayarlar → solda takvimin → *Takvimi entegre et* → **iCal biçiminde gizli adres**
- **Outlook.com:** Ayarlar → Takvim → Paylaşılan takvimler → *Takvim yayımla* → **ICS** bağlantısı

Takvim beş dakikada bir indirilir; ada yalnızca sıradaki etkinliği gösterir ve 5 dakika kala bir kez
hatırlatır. Bu adres bir paroladır: kimseyle paylaşma. `%APPDATA%\DinamikAda\settings.json` içinde,
yalnızca senin Windows kullanıcının okuyabileceği yerde durur.

### Dosya rafı

Bir dosyayı sürükleyip adaya yaklaştırınca ada bırakma alanına dönüşür; bırakınca rafa girer (en
fazla 6). Kontrol Merkezi'ndeki RAF satırında: tıkla → aç, Ctrl/Shift-tıkla → seç, sürükle → dışarı
çıkar, sağ tık → Aç, Gezgin'de Göster, Kopyala, **Paylaş** (Windows paylaşım penceresi, Yakındaki
paylaşım dahil), Şuraya Taşı…, Kaldır.

---

## macOS sürümünden farklar — dürüst liste

- **Notch yok.** Ada her zaman simüle pil olarak ekranın üst ortasında durur. Ekranın o bölgesi
  tarayıcı sekmeleri ve pencere başlıklarına denk gelir; ada kompaktken dar (210×32) ve şeffaf
  kısımlar tıklamayı alttaki uygulamaya geçirir, ama üzerine gelince açılır. Rahatsız ederse
  Ayarlar'dan adayı başka bir ekrana alabilirsin.
- **Bildirim aynası yok.** Windows, paketlenmemiş uygulamaların başka uygulamaların bildirimlerini
  okumasına izin vermiyor.
- **Bırakma alanı sürüklemenin başında değil, adaya yaklaşınca açılır.** Windows'ta "bir dosya
  sürüklenmeye başladı" diye genel bir bildirim yok (macOS sürükleme panosunu yokluyordu).
- **AirPods sol/sağ/kutu ayrımı yok.** Windows yalnızca tek bir pil değeri yayınlıyor; o da her
  kulaklıkta yok.
- **Parlaklık yalnızca dahili ekranda.** Harici monitörler WMI parlaklık arayüzünü desteklemez;
  masaüstü bilgisayarda modül görünmez. Parlaklık tuşları çoğu dizüstünde donanımda işlendiği için
  devralınamaz; Windows'un parlaklık göstergesi adayla birlikte görünmeye devam eder.
- **"Dahili ekran" seçeneği yok.** Otomatik, ana ekranı seçer; listedeki her ekran ayrıca seçilebilir.
- **Ses tuşlarını devralmak izin istemez** (macOS'ta Erişilebilirlik gerekiyordu). Yine de sistemin
  davranışını değiştirdiği için varsayılan kapalı.
- **Ses adımı:** Windows sesi %2'lik adımlarla oynatır. Ses tuşları devralınınca her basış tam %5
  (Shift+Alt: %1) olur.

---

## Dosyalar

| Ne | Nerede |
|---|---|
| Ayarlar (iCal bağlantısı dahil) | `%APPDATA%\DinamikAda\settings.json` |
| Raftaki dosyaların listesi | `%APPDATA%\DinamikAda\shelf.json` |
| Uygulama (install.ps1 ile) | `%LOCALAPPDATA%\Programs\DinamikAda\DinamikAda.exe` |
| Oturum açılınca başlatma | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\DinamikAda` |

---

## Geliştirme

```powershell
dotnet build Windows\DinamikAda.Windows.csproj
dotnet publish Windows\DinamikAda.Windows.csproj -c Release -r win-x64   # tek dosyalık DinamikAda.exe
```

Proje `EnableWindowsTargeting` açık olduğu için Linux ve macOS'ta da derlenir (çalışmaz, ama derleme
hatalarını görmek için yeter). Simge `python Windows\Scripts\make_icon.py` ile üretilir (Pillow).

Bağımlılıklar: [NAudio](https://github.com/naudio/NAudio) (MIT, ses), `System.Management`
(Microsoft, WMI parlaklık), [Ical.Net](https://github.com/rianjs/ical.net) (MIT, takvim).

```
Windows/
├── DinamikAda.Windows.csproj  .NET 10, WPF
├── App.xaml(.cs)              Giriş, tek örnek, bildirim alanı
├── Core/                      Ayarlar, iki dilli metinler, simge kodları
├── Island/                    Model, yük tipleri, zamanlayıcı, raf, geometri, denetleyici
├── Monitors/                  Medya, ses, parlaklık, pil, Bluetooth, gizlilik, indirmeler,
│                              takvim, ses tuşları, tam ekran, ekranlar, Win32 çağrıları
├── UI/                        Ada penceresi, şekil, yay animasyonu, içerikler, ayarlar, menü
├── Scripts/make_icon.py       Simgeyi çizer
└── install.ps1                Kaynaktan derleyip kurar
```

Geometrinin tek kaynağı `Island/IslandLayout.cs`: görünüm denetimleri oradan konumlandırır, tıklama
dikdörtgenleri de aynı çağrılardan türetilir. Sayılar macOS sürümüyle (`IslandLayout.swift`,
`IslandPayloads.swift`) aynı; bir tarafta değişirse diğer tarafa da taşınmalı.
