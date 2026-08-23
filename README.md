# MacBook Notch için Dynamic Island — Faz 1–5

MacBook notch'unun çevresine etkileşimli bir **Dynamic Island tarzı katman**
çizen, yerel (native) bir macOS menü çubuğu uygulaması. Yerel görünür ve
hisseder, gerçek SwiftUI yaylarıyla (spring) animasyon yapar ve simüle notch
modu sayesinde (fiziksel notch olsun ya da olmasın) **her** Mac'te gösterime
uygundur.

**Faz 1** arayüz temeli ve etkileşim modelidir. **Faz 2** adayı gerçek sistem
verisine bağlar: Now Playing, ses, parlaklık, pil. **Faz 3** zamanlayıcıyı,
AirPods/Bluetooth pilini ve kamera/mikrofon göstergelerini ekler. **Faz 4**
dosya sürükle-bırakı ve geçici dosya rafını getirir. **Faz 5** takvimi, çoklu
ekran seçimini ve bildirim aynasını ekler. **Faz 6** sistemin yerine geçmeye
çalışır: sistem geneli Now Playing (tarayıcı medyası dahil), sistem HUD'unun
yerini alma, tam ekranda çekilme, indirme etkinliği ve Raf 2.0.

### Üç durumun adı

Bu belgede ve konuşurken kullanılan adlar:

| Ad | Ne zaman |
|---|---|
| **ada** | Boştaki hâli — notch'a yaslanan kompakt pil |
| **dinamik** | Üzerine gelince (hover) açılan tek satır |
| **dinamik ada** | Tıklayınca açılan kontrol merkezi |

---

> ✅ **Durum: Mac üzerinde derlendi ve çalıştırıldı** (Xcode 26.4, macOS 26.5,
> Apple Silicon), uyarısız.
>
> Canlı doğrulananlar: katmanın notch üzerine konumlanması, kompakt durum,
> hover → genişleme, ada dışında tıklama geçişi; **ses HUD'u** (sistem sesi
> değiştirilip ada üzerinde okundu); **pil** ve **parlaklık** okumaları (`pmset`
> ile karşılaştırıldı); **Now Playing** — parça bildirimi yayınlanıp kompakt
> aksesuarların belirmesi, parça değişiminin anında yansıması ve duraklatmada
> dalga formunun donması ölçüldü; **ses HUD'unun medyayı devralıp geri vermesi**;
> **18 saniyelik boşta testi** (ada kendiliğinden hiç açılmadı).
>
> Ayrıca ölçülenler: `hitTest` dört durumda da `PassthroughHostingView`
> döndürüyor (tıklama yönlendirmesinin doğru katmana ulaştığının kanıtı) ve
> çizilen transport düğmeleri ile tıklanabilir dikdörtgenler birebir çakışıyor.
> Adanın bütün durumları offscreen render ile tek tek doğrulandı.
>
> Etkileşim katmanı, panele gerçek `NSEvent`'ler gönderilerek test edilir
> (`mouseDown`/`mouseDragged`/`mouseUp` → doğru geri çağrı ve değer): oynat-duraklat,
> sonraki parça, ses sürükleme (%25 → %80), parlaklık tıklaması, ada gövdesine
> tıklama ve pil kutucuğunun tepkisizliği — altısı da geçiyor.
>
> Kompakt pilin notch ile birebir çakıştığı sayısal olarak doğrulandı
> (663…848, sapma 0,0 pt).
>
> Ayar turu: %5 ızgarasının gerçekten temiz bir dizi ürettiği ölçüldü (%50'den
> yukarı 55/60/65/70/75/80, aşağı 45/40/35/30/25/20) ve canlı doğrulandı — sistem
> sesi ızgara dışı bir değere ayarlandığında uygulama onu oturtuyor (62→60, 31→30,
> açılışta 44→45). Genişletilmiş ada artık içeriğine göre daralıyor (üç çipli
> hover 380 → 286 pt).
>
> Faz 6 tüketimi ölçüldü (10 sn ısınma sonrası 60 sn pencerede CPU-zamanı farkı,
> boşta): **Faz 6 modülleri kapalıyken %1,57 → açıkken %2,42**, yani yaklaşık
> **0,85 puan**. Neredeyse tamamı tam ekran algılayıcısının pencere listesi
> yoklaması; ikisi de `Ayarlar → Davranış`'tan kapatılabilir. (Faz 3'teki %0,7
> rakamı artık geçerli değil — Faz 4 ve 5 kendi izleyicilerini ekledi; bugünkü
> temel %1,57.) Bellek 100–118 MB aralığında dalgalanıyor ve modül sayısıyla
> anlamlı biçimde ilişkilenmiyor.
>
> Faz 6: uyarısız derleniyor ve çalışıyor. `DownloadMonitor` izole olarak
> sınandı — büyüyen kısmi dosya, eşzamanlı ikinci indirme, `.crdownload` → tam
> dosya yeniden adlandırması (tam bir kez, doğru adla), önceden var olan
> dosyaların anons edilmemesi ve iptalin etkinliği temizlemesi: beş savın hepsi
> geçiyor. `Vendor/` boru hattı sahte artefaktlarla doğrulandı — framework
> klasörü olduğu gibi, betik yanına kopyalanıyor; klasör boşken üretilen proje
> eskisiyle aynı. **Henüz canlı doğrulanmadı:** medya tuşu yakalama
> (Erişilebilirlik izni ister), tam ekran algılama ve MediaRemote yolu — sonuncusu
> adapter ikilileri konmadan hiç çalışmaz.
>
> Faz 5: bölüm yığını refaktöründen sonra beş bölüm birden açıkken yerleşim ve
> 20 etkileşim testinin tamamı doğrulandı; etkinlik metni biçimlendirmesi ve ekran
> tercihinin saklanması/geri düşmesi ayrıca sınandı.
>
> Faz 4: sürükleme algılama, raf (ekleme / yinelenmeme / kaldırma / kalıcılık /
> silinmiş dosyanın ayıklanması) ve gerçek bir `performDragOperation` bırakma
> olayı — 18 testin tamamı geçiyor. Kontrol Merkezi etkileşim paketi 20 teste
> çıktı (raf dosyaları, ✕ rozeti, Copy/AirDrop/Clear dahil), hepsi geçiyor.
>
> Faz 3: zamanlayıcı durum makinesi (başlat / duraklat — duraklıyken kaymadığı
> ölçüldü / devam / yeniden başlat / iptal / bitiş) ve 12 etkileşim testinin
> tamamı geçiyor. Kamera ve mikrofon algılamasının gerçekten sayım yaptığı
> doğrulandı (6 giriş aygıtı, 4 kamera bulundu, hepsi sorgulanabilir). Boştaki
> tüketim: **CPU %0,7, bellek 81 MB**, sabit.

---

## Faz 1 neleri içerir

- **Menü çubuğu ajan uygulaması** (`LSUIElement`): Dock simgesi yok, menü
  çubuğundan çalışır. Durum öğesi, yerel bir menüye sahip bir kapsül simgesidir:
  - Çalan parça, zamanlayıcı, raf ve sıradaki etkinliğin durumu
  - `Start Timer` (1–60 dk alt menüsü)
  - `Demo: Expand Island` / `Demo: Show Control Center`
  - `Settings…` (Ayarlar)
  - `Quit Dynamic Island` (Çıkış)
- **Kenarlıksız, saydam, etkinleştirmeyen katman** (`.nonactivatingPanel` +
  `.borderless` özellikli `NSPanel`, `.statusBar` seviyesi, koleksiyon davranışı
  `.canJoinAllSpaces` + `.fullScreenAuxiliary` + `.stationary`). Her Space'te
  diğer uygulamaların üzerinde yüzer ve **ekranın üst-ortasında, notch ile
  hizalı** konumlanır.
- **Ada dışında her yerde tıklama geçişi (click-through).** Yalnızca adanın
  güncel şekli fare olaylarını yakalar; başka herhangi bir yere yapılan
  tıklamalar doğrudan alttaki uygulamaya geçer
  (`PassthroughHostingView.hitTest` içinde uygulanmıştır).
- **Ada notch'un gerçek eksenine hizalanır.** Kesik her panelde tam ortada
  değildir — bu makinede 663…848 arası, yani merkezi 755,5 iken ekran merkezi
  756'dır. Ekrana göre hizalamak kameranın yanında 1pt'lik siyah şerit bırakıyordu;
  artık `notchCenterX` kullanılıyor ve kompakt pil notch ile **birebir** çakışıyor
  (185 × 32 pt). Kompakt durumda gölge de çizilmez: ada kesiğin *içinde* durduğu
  için gölge yalnızca kameranın çevresine leke bırakırdı.
- **Notch algılama**, gerçek notch genişliği/yüksekliği ve merkezini hesaplamak
  için genel (public) macOS 12+ API'leri ile (`NSScreen.safeAreaInsets`,
  `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`). Fiziksel notch yoksa,
  uygulamanın her yerde gösterilebilmesi için bir **simüle notch** pili çizilir.
  Ekran/çözünürlük değişiklikleri izlenir
  (`NSApplication.didChangeScreenParametersNotification`) ve katman otomatik
  olarak yeniden konumlanır.
- **Ada durumları**, yerel yay animasyonlarıyla:
  - **Compact (Kompakt)** — notch'a yaslanan küçük, gerçek siyah yuvarlak pil.
  - **Expanded (Genişletilmiş)** — daha geniş bir yuvarlak dikdörtgen.
  - **Control Center (Kontrol Merkezi)** — iki bölümlü daha büyük bir panel.
- **Üzerine gelme (hover)** adayı genişletir; **ayrılma** onu (otomatik toplanma
  gecikmesinden sonra) toplar. **Tıklama** tam Kontrol Merkezi durumunu açıp
  kapatır.
- **Gerçek siyah dolgu, notch'a uyan yuvarlak köşeler, hafif gölge** ve ince bir
  vurgu çizgisi. Ada her zaman koyudur (donanım notch'u gibi), bu yüzden hem
  Açık hem Koyu modda doğru görünür.
- **Yerel Ayarlar penceresi** (SwiftUI `Settings` sahnesi): ekran seçimi, ada
  boyutu, animasyon hızı, otomatik toplanma gecikmesi, modül anahtarları.

---

## Dil

Uygulama **Türkçe ve İngilizce**. `Ayarlar → Genel → Dil`'den anında değişir,
yeniden başlatma gerekmez. İlk açılışta sistem diline bakılır: Mac Türkçeyse
Türkçe, değilse İngilizce.

Çeviriler `Localizable.strings` yerine tek bir dosyada, çiftler hâlinde durur
(`App/Localization.swift`). Sebebi: uygulama sistem dilini izlemek yerine bir
**seçici** sunuyor; standart mekanizma sistemin seçimi etrafında kurulu ve onu
çalışma anında değiştirmek zaten başka bir bundle yükleyip her metni yeniden
okumak demek. İki dilli, çevirmensiz bir uygulamada kod içinde tutmanın daha iyi
bir özelliği var: **eksik çeviri derleme hatası olur**, sessizce İngilizce kalan
bir metin olmaz.

İki ayrıntı Türkçe için özel olarak halledildi:

- **Noktalı/noktasız I.** Bölüm başlıkları büyük harfe çevrilirken yerel ayar
  kullanılır; düz `uppercased()` "Sistem"i **SISTEM** yapıyordu, doğrusu
  **SİSTEM**.
- **Etiket genişlikleri ölçülür, tablodan gelmez.** Raftaki Copy/AirDrop/Clear
  düğmelerinin genişliği İngilizceye göre sabitlenmişti; "Kopyala" (41pt) "Copy"
  için ayrılan 28pt'ye sığmıyordu. Artık çizilecek metin ölçülüyor, dolayısıyla
  çizilen etiket ile tıklanabilir alan her dilde aynı.
- Tarih ve saatler de seçilen dilin yerel ayarını kullanır, sistemin değil.

---

## Etkileşim mimarisi

Adadaki **her tıklama ve hover AppKit tarafında, geometriyle** çözülür; SwiftUI
yalnızca çizer. Bu bir tercih değil, zorunluluk: `NSHostingView` içeriği için alt
görünüm üretmez, hit-test'i kendi içinde yapar ve daima kendini döndürür. Yani
bir tıklama ya bizim `PassthroughHostingView`'umuza ulaşır ya da SwiftUI'ın kendi
jest sistemine — ve o sistem, hiçbir zaman *key* olmayan bir panelde, neredeyse
hiç öne gelmeyen bir uygulamada güvenilir çalışmaz. (Bu ölçüldü: dört durumda da
`hitTest` `PassthroughHostingView` döndürüyor.)

Bunun üç sonucu var:

- Transport düğmelerinin konumu `ControlCenterMetrics.transportFrames` ile **tek
  bir yerde** hesaplanır. Görünüm ikonları oraya yerleştirir, `IslandLayout` aynı
  çağrıdan tıklama dikdörtgenlerini türetir — gördüğün düğme ile basabildiğin
  düğme ayrışamaz.
- Düğme hover vurgusu da `.onHover` yerine imleç örneklemesinden gelir.
- Ses/parlaklık sürüklemesi `mouseDown` → `mouseDragged` → `mouseUp` zinciriyle
  yürür. Bir `mouseUp` kaçarsa sürükleme kilitlenip adayı açık bırakmasın diye
  her imleç örneklemesinde `NSEvent.pressedMouseButtons` ile kontrol edilir.

**Ada içeriğine göre daralır.** Genişletilmiş durum eskiden her yük için sabit
380pt idi; kısa içeriklerin iki yanında geniş siyah kanatlar kalıyordu. Artık her
yük ne kadar yer gerektiğini söylüyor (üç çipli hover 286pt, ses HUD'u 320pt,
Now Playing 360pt). Panel penceresi yine sabit — en geniş hâle göre bir kez
ölçülür, böylece her yük değişiminde pencere yeniden konumlanmaz.

**Kapanma:** imleç adadan ayrılınca varsayılan **0,5 saniyede** toplanır (eskiden
2 sn idi ve ada gitmemekte direniyor gibi hissettiriyordu), **başka bir yere
tıklanınca ise anında**. Dışarı tıklama, her şey gibi, imleç örneklemesinden
yakalanır: imleç adanın dışındayken başlayan bir basış. Dosya sürüklemesi tuşu
basılı tuttuğu için bundan muaf.

Ayrıca **hover alanı cömert, tıklama alanı tam**: kompakt pil tam olarak notch'un
üstünde durduğu için nişan alınacak bir şey yoktur, o yüzden hover adanın 12×8pt
dışına kadar çalışır; ama o kenar boşluğuna yapılan tıklama alttaki pencereye
gider.

---

## Faz 2 neleri içerir

Ada artık yer tutucu değil, gerçek sistem durumunu gösteriyor. İki tür içerik
adayı paylaşır:

- **Kalıcı (ambient)** — Now Playing. Çaldığı sürece kompakt pilin iki yanında
  yaşar.
- **Anlık (transient)** — ses, parlaklık, güç. Adayı ~1,7 saniye devralır,
  sonra geri verir. Kullanıcının bilerek açtığı Kontrol Merkezi'ni **asla**
  ezmez.

### Modüller

| Modül | Kaynak | İzin |
|---|---|---|
| **Now Playing** | MediaRemote (Faz 6, varsa) → Music + Spotify dağıtık bildirimleri | **yok** (yedek yolda kapak + düğmeler için Otomasyon) |
| **Ses** | CoreAudio property listener (olay tabanlı) | yok |
| **Parlaklık** | DisplayServices (private, `dlopen`) | yok |
| **Pil / Güç** | IOKit Power Sources (olay tabanlı) | yok |

- **Parça algılama bildirim tabanlıdır, yoklama değil.** Music ve Spotify her
  parça/durum değişiminde sistem geneline bildirim yayınlar
  (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`) ve
  bu bildirim parça adını, sanatçıyı ve çalma durumunu zaten taşır. Sonuçları:
  değişim **anında** yansır (yoklamada bir sonraki tur beklenirdi), **hiç izin
  gerektirmez** ve izin reddedilse bile sessizce ölmez. AppleScript yalnızca
  bildirimlerin veremediği üç şey için kullanılır: albüm kapağı, uygulama
  açılmadan önce çalmaya başlamış bir oynatıcının durumu ve transport komutları.
- **Kompakt aksesuarlar:** müzik çalarken kompakt pil genişler; notch'un
  **solunda albüm kapağı**, **sağında canlı dalga formu** belirir — iPhone'daki
  Dynamic Island'ın imza görünümü. Duraklatılınca dalga formu donar.
- **Ses / parlaklık HUD'u:** simge + kapsül metre + yüzde. Sistemin kendi
  HUD'unun dilini kullanır (SF Symbols, tek boşluklu rakamlar).
- **Seviyeler %5'in katlarında.** macOS ikisini de on altıda birlik adımlarla
  hareket ettirir, yani ada 6, 13, 19, 25… sayardı. Yalnızca etiketi yuvarlamak
  çözmez (dizi 5, 15, 20, 30… olur, aralıklar bozuk); değerin kendisi ızgaraya
  oturtulur. Oturduktan sonra sistemin ±%6,25'i bir sonraki beşliğin yarım adım
  yakınına düşer, dolayısıyla **her basış tam %5** eder. Ölçüldü: %50'den yukarı
  55, 60, 65, 70, 75, 80 — ızgarasız hâli 56, 63, 69, 75, 81, 88 idi.
  %3'ün altındaki değişimler dokunulmadan bırakılır, yoksa sesini yumuşakça kısan
  bir uygulamayla kavga edilirdi. `Settings → Snap volume & brightness to 5%`.
- **Güç HUD'u:** fişe takıldığında/çıkarıldığında "Power Adapter" / "On Battery",
  yüzde ve (sistem tahmin ediyorsa) kalan süre.
- **Hover, müzik yokken:** pil, ses ve parlaklığı tek bakışta veren üç çip.
- **Kontrol Merkezi:** NOW PLAYING (kapak, parça, sanatçı, kaynak + çalışan
  önceki/oynat-duraklat/sonraki düğmeleri) ve SYSTEM.
- **Ses ve parlaklık gerçekten ayarlanır.** SYSTEM satırındaki ses ve parlaklık
  kutucukları sürüklenebilir: basınca anında uygulanır, sürükleyince takip eder.
  Hedef alan kutucuğun tamamıdır — 6pt'lik bir çubuğa nişan almak zordur, macOS'un
  kendi Kontrol Merkezi de aynı şekilde davranır. Ses `AudioObjectSetPropertyData`
  ile (genel API), parlaklık `DisplayServicesSetBrightness` ile yazılır; sesi
  yukarı çekmek sessize almayı da kaldırır. Pil kutucuğu salt göstergedir ve
  tıklamayı yutar, panel altından kapanmaz.
- **Otomatik parlaklık ayıklanır.** macOS ortam ışığına göre parlaklığı sürekli
  minik oynatır; bunlar ada açılması için sebep değildir. Yalnızca tek örnekte
  eşiği (%1,5) aşan sıçramalar — yani parlaklık tuşuna basmak — HUD açar. Sürüklenme
  yine de okunan değeri günceller, sadece kimseyi rahatsız etmez.
- **"Demo:" menü öğeleri kendiliğinden çözülür** (8 sn). Süresiz bir sabitleme,
  yanlışlıkla tıklandığında adayı açık bırakıp donmuş gibi gösteriyordu.
- **Ayarlar:** her modül tek tek kapatılabilir (kapatılan modülün izleyicisi
  tamamen durur), artı **Launch at Login** (`SMAppService`), Otomasyon izninin
  canlı durumu ve algılanan notch ölçüsü. Faz 6'da **Davranış** bölümü eklendi:
  sistem HUD'unu değiştirme, tam ekranda gizlenme ve ekran görüntüsü gizliliği.
- **Teşhis görünür.** Menü çubuğu menüsü çalan parçayı gösterir; Otomasyon
  reddedilmişse hem menüde hem Ayarlar'da yazar ve doğrudan ilgili sistem
  ayarına götürür. Menü çubuğu ajanının şikâyet edecek penceresi olmadığı için
  sorunun sessizce kaybolmaması önemli.

---

## Faz 3 neleri içerir

### Zamanlayıcı

- Kontrol Merkezi'ndeki TIMER satırından **5 / 10 / 25 dakika** tek tıkla başlar.
  Menü çubuğundaki `Start Timer` alt menüsünde 1'den 60 dakikaya kadar tam liste
  var — serbest süre girişi klavye ister, bu panel ise hiçbir zaman *key* olamaz.
- Çalışırken kompakt pilde geri sayım görünür: notch'un solunda saat simgesi,
  sağında `12:34`. Müzik de çalıyorsa kapak solda kalır, geri sayım sağı alır.
- Satır çalışırken **duraklat / yeniden başlat / iptal** düğmelerine dönüşür,
  yanında ilerleme çubuğu.
- Kalan süre saatten türetilir, tick'lerle azaltılmaz: tekrarlayan bir zamanlayıcı
  kayar ve uyku sırasında beklendiği gibi tetiklenmez; saati okumak, tick ne kadar
  kaba olursa olsun doğru sonucu verir.
- Bitince kısa bir sistem sesi (`Sound effects` ile kapatılabilir) ve adada
  "Timer finished" bildirimi.

### AirPods / Bluetooth pili

- Bağlanınca ada kısaca açılır: cihaz adı, `Connected`, ve pil — AirPods için
  **sol / sağ / kutu** ayrı ayrı, diğer kulaklıklar için tek değer.
- Seviyeler `system_profiler SPBluetoothDataType` ile okunur — sistemin kendi
  Bluetooth menüsünün kullandığı kaynak. Alt süreç olduğu için **bize Bluetooth
  izni gerekmez**.
  > İlk uygulama IO registry'deki `BatteryPercentLeft` vb. anahtarları okuyordu;
  > bu makinede o anahtarlar **hiç yok**, dolayısıyla kod çalışıyor gibi görünüp
  > hiçbir zaman ateşlenmiyordu. Aynı sınıf hatanın (AppleScript'e bağlı Now
  > Playing) tekrarıydı.
- `system_profiler` 1–2 saniye sürdüğü için asla sık yoklanmaz. AirPods kendini
  çok daha ucuz bir yoldan duyurur: bağlanınca bir ses çıkış aygıtı eklenir ve
  CoreAudio aygıt listesinin değiştiğini bildirir. Tetikleyici odur; arkasındaki
  yavaş tazeleme (5 dk) yalnızca yüzdeleri bayatlamaktan korur.
- Yüzdeler metin olarak gelir ve işaret yerel ayara göre iki yana da düşebilir
  ("99%" / "%99"); ikisi de ayrıştırılır.
- Pil bildirmeyen cihazlar (klavye, fare) elenir.
- Bağlı bir cihaz Kontrol Merkezi'ndeki SYSTEM satırında **kalıcı bir kutucuk**
  olarak da durur; yalnızca bağlanma anındaki iki saniyede değil, istediğin an
  bakabilirsin.

### Kamera / mikrofon göstergeleri

- Kompakt pilde macOS'un kendi gizlilik göstergesiyle aynı renklerde iki nokta:
  **yeşil kamera**, **turuncu mikrofon**.
- Kamera veya mikrofon kullanımdayken bu noktalar albüm kapağının önüne geçer —
  kaydedildiğini bilmek, ne çaldığını bilmekten önemlidir.
- İkisi de "donanım bir yerlerde çalışıyor mu" sorusuyla bulunur (mikrofon için
  CoreAudio, kamera için CoreMediaIO). Hiçbir akış açılmaz, dolayısıyla **kamera
  veya mikrofon izni istenmez**: uygulama neyin kaydedildiğine değil, yalnızca
  kayıt olduğu bilgisine erişir.
- Bu ek bir gösterge; macOS'un kendi göstergesi hâlâ asıl kaynaktır.

---

## Faz 4 neleri içerir

### Bırakma alanı

- Bir dosyayı sürüklemeye başladığın anda ada büyük, kesik çizgili bir **bırakma
  alanına** dönüşür; üzerine geldiğinde "Release to keep" der ve vurgulanır.
- Buradaki asıl problem şuydu: panel, imleç adanın üstünde değilken tamamen
  inert — menü çubuğu tıklanabilir kalsın diye. Ama fare olaylarını yok sayan bir
  pencere **sürüklemeleri de** reddeder, ve AppKit henüz bizim bir görünümümüze
  girmemiş bir sürüklemeden haberdar etmez. Yani paneli, sürükleme havadayken
  önceden uyandırmak gerekiyordu.
- Çözüm iki ucuz gerçeğe dayanıyor, ikisi de izin istemiyor: sistem sürükleme
  panosunun `changeCount`'u herhangi bir uygulama sürüklemeye başladığında
  değişir, ve sürükleme boyunca sol tuş basılı kalır. "Tuş basılı **ve** pano
  son bırakılıştan beri değişmiş" = şu anda bir sürükleme var; panonun içeriği de
  dosya taşıyıp taşımadığını söyler.

### Raf

- Bırakılan dosyalar rafta durur (en fazla 6, en yenisi başta). Uygulama
  kapanıp açılsa da kalırlar.
- Kontrol Merkezi'ndeki SHELF satırında gerçek Finder ikonlarıyla görünürler.
  Dosyaya tıklamak açar; üzerine gelince çıkan **✕** rafından çıkarır. Sağdaki
  **Copy / AirDrop / Clear** hepsine birden uygular.
- **Dosyayı raftan geri sürükleyebilirsin** — rafın asıl anlamı bu. Chip'e
  basıp sürüklemek gerçek bir `NSDraggingSession` başlatır, Finder'a ya da başka
  bir uygulamaya bırakabilirsin.
- Yollar saklanır, yer imi değil: uygulama sandbox'sız olduğu için yol yeterli ve
  raf zaten *geçici* — taşınmış ya da silinmiş bir dosya, şaşırtıcı bir yere
  çözülen bir yer imi olarak kalmak yerine sessizce raftan düşer.
- Kompakt pilde raf doluyken tepsi simgesi ve dosya sayısı görünür.

---

## Faz 5 neleri içerir

### Takvim

- Kontrol Merkezi'nde **UP NEXT** satırı: sıradaki etkinliğin adı, yeri, saati ve
  "in 12 min" gibi kalan süresi. Etkinliğe 5 dakika kalınca ada bir kez kısaca
  açılıp hatırlatır.
- **Varsayılan olarak kapalı.** İzin isteyen tek modül bu; ilk açılışta habersiz
  takvim izni soran bir katman, henüz kazanmadığı bir güveni harcamış olur.
  Açtığında Ayarlar'da izin durumu ve bir "Allow…" düğmesi çıkar; reddedildiyse
  doğrudan ilgili sistem ayarına götürür.
- Tüm gün süren etkinlikler elenir — randevu değil bağlam bilgisidir ve gün boyu
  adada durup bir şey söylemez.
- Kalan dakika aşağı yuvarlanır: yuvarlansaydı son yarım dakika "in 1 min",
  ondan önceki yarım dakika "now" derdi.

### Çoklu ekran

- Ayarlar'da **Display** seçici: *Automatic* (varsa dahili notch'lu ekran, yoksa
  ana ekran), *Built-in*, ya da bağlı harici ekranlardan biri.
- Tercih ekranın **UUID**'siyle saklanır, `CGDirectDisplayID` ile değil: ID monitör
  çıkarılıp takılınca yeniden atanır ve kayıtlı tercih sessizce yanlış ekranı
  gösterirdi.
- Seçilen ekran bağlı değilse kademeli olarak geri düşer — hiçbir ekranda olmayan
  bir ada, uygulama çökmüş gibi görünürdü.
- Notch'u olmayan bir ekranda simüle pil çizilir.

### Bildirimler — yapılmadı, sebebi aşağıda

---

## Faz 6 neleri içerir

Bu faz üç şeyi hedefliyor: sistemin *yerine geçmek* (HUD), sistemin *göremediğini
görmek* (tarayıcı medyası), ve adanın *yolda durmamasını* sağlamak.

### Sistem geneli Now Playing — tarayıcı medyası dahil

Faz 2'nin en büyük sınırı buydu: Now Playing yalnızca Music ve Spotify'ı
görüyordu, çünkü sistem genelindeki kaydı tutan private `MediaRemote`
framework'ü macOS 15.4'te paket kimliği `com.apple.` ile başlamayan proseslere
kapatıldı.

Yol şu: `/usr/bin/perl` bir Apple ikilisidir ve paket kimliği `com.apple.perl5`
— yani o kontrolü geçer.
[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
küçük bir yardımcı framework'ü Perl prosesinin *içine* yükler, MediaRemote ile
orada konuşur ve sonucu stdout'a JSON satırları olarak yazar. Uygulama onu alt
proses olarak çalıştırıp okur; **bu uygulamaya hiçbir private API linklenmez.**

| | Faz 2 yolu | MediaRemote yolu |
|---|---|---|
| Görülen oynatıcılar | Music + Spotify | Safari, Chrome, YouTube, VLC, IINA, Podcasts — hepsi |
| Kapak ve düğmeler | Otomasyon izni ister | **izin yok** |
| Uygulamadan önce başlamış çalma | görünmez | anında görünür |
| Geçen süre / sürgü | yok | var |

- **Konum her okumada birleştiriliyor.** Betik sonucu yalnızca parça ya da çalma
  durumu *değiştiğinde* saklanıyordu; bildirim yolu parçayı önce kurduğu için
  sonraki okumalar "aynı parça" deyip atlıyor, dolayısıyla süre ve konum hiç
  içeri girmiyordu — `hasProgress` sonsuza dek false kalıyor ve sürgü hiç
  görünmüyordu. Artık aynı parçada da zamanlama katılıyor: başlık, sanatçı ve
  çalma durumu hâlâ bildirimlerin, yalnızca oynatma kafası betiğin.
- **Tek aksesuar varken pil doğru hizalanıyor.** Pil bir aksesuar yuvası, notch
  ve öteki yuvadan oluşuyor; bütünü notch'un *merkezine* hizalamak, notch
  şeridini kesiğin üstüne ancak iki yuva eşit genişlikteyse getiriyor. Tek
  aksesuarla — hiçbir şey çalmazken bir indirme, mesela — pil her iki yana
  yarım aksesuar kadar büyüyor ve glifin yarısı kamera muhafazasının arkasında
  kalıyordu; ekranda yarım bir sembol olarak görünmesinin sebebi buydu. Artık
  fark kadar kaydırılıyor: şerit yerine oturuyor ve pil yalnızca ihtiyaç duyulan
  tarafa büyüyor. Kaydırma çizimle hit rect arasında paylaşılıyor, ikisi ayrışamaz.
- **İndirme göstergesi kameranın solunda.** Eskiden okun sabit bir negatif
  kaydırmayla tepsi glifinin *üstüne* yığılması onu notch şeridinin dışına
  taşırıyordu: adanın kendi dış hattı kırpıyor ve ekranda yarım, bozuk bir sembol
  gibi görünüyordu. Yeni glifin her parçası açık bir çerçeveyle sınırlı ve yuva
  kapağın kullandığı sol tarafa alındı — genişlik de diğer aksesuarlarla aynı
  (34pt), yani pil kameranın soluna doğru düzgün büyüyor.
- **Sürgü artık adapter'sız da çalışıyor.** İlerleme başta yalnızca MediaRemote'tan
  geliyordu, yani `Vendor/` boşken hiç görünmüyordu. Oysa Music ve Spotify konumu
  ve süreyi **AppleScript ile de** veriyor — üstelik zaten yapılan aynı gidiş
  dönüşte. Artık parça okunurken `player position` ve `duration of current track`
  de okunuyor, sürükleyince `set player position to …` yazılıyor.
  - Music süreyi **saniye**, Spotify **milisaniye** veriyor ve yanıtta hangisi
    olduğunu söyleyen bir şey yok; kaynaktan çıkarılıyor.
  - Sayılar sistemin yerel ayarıyla biçimleniyor: Türkçe bir Mac'te
    `64,092002868652` geliyor, yani ondalık ayırıcı **virgül**. Ayrıştırmadan
    önce noktaya çevriliyor, yoksa `Double(...)` nil döner ve sürgü sessizce
    kaybolurdu.
  - MediaRemote adapter'ı varsa yine o kazanır: tarayıcı medyasını da görür ve
    konumu bir betik çağrısı olmadan verir.
- **Sürgü yalnızca dinamik ada'da.** Üzerine gelince açılan satır tek satırlık
  bir bilgi; sürgü bir tık daha derinde duruyor. Böylece **dinamik** hâlin
  yüksekliği tek bir sayı oldu (56pt), süreye göre değişmiyor.
- **Başlık hedefi tek satıra indirildi.** Başlık bloğunun tamamı basılabilir
  olunca adayı *açmak* için tıklanacak yer kalmıyordu — "aç" diye uzanıp
  "Spotify'a geç" almak. Artık yalnızca başlık satırı (17pt), yani 56pt'lik
  satırın geri kalanı ve adanın gövdesi açma tıklamasına ait: ölçüldü, adanın
  **%80'i** hâlâ boş.
- **Sürgü dinamik ada'da.** Medya satırı süre bilindiğinde uzuyor ve
  altına sürgü ile geçen/kalan süre giriyor. Satır yüksekliği `ControlCenterSections`
  üzerinden taşınıyor — panel bundan boyutlandığı için süreyi yayınlamaya başlayan
  bir parça adayı yeniden boyutlandırmalı, taşırmamalı.
  - Hit sırası önemli: 3pt'lik bir çubuk yakalanabilmek için dikey büyütülmüş bir
    basma alanı istiyor, o alan da başlık bloğuna geri uzanıyor. İlk eşleşme
    kazandığı için sürgü başlıktan **önce** ekleniyor — başka türlü hiç
    yakalanamayacak olan o.
- **Kapağa basmak uygulamayı açar.** Yalnızca kapak: başlık da basılabilir
  yapılmıştı ama adayı *açmak* için tıklanacak yeri yiyordu, kaldırıldı.
- **İlerleme çubuğu ve sürgü.** MediaRemote bir *konum* ve bir *zaman damgası*
  verir, tıkırdayan bir saat değil — çubuk bu yüzden saatten ileri sarılarak
  (`elapsedNow`) çizilir, yoksa yalnızca parça değişince kımıldardı. Çubuk
  basıp sürüklenebilir; hedef alanı çubuğun kendisinden dikey olarak büyütülür,
  çünkü 3pt'lik bir şeye nişan alınamaz. Süre bilinmiyorsa çubuk **hiç
  çizilmez** — boş bir çubuk, bilgi yokluğunu bilgi gibi gösterir.
- **Bozulmadan geri düşer.** Adapter yoksa (temiz bir klonun normal hâli) ya da
  bir gün çalışmayı bırakırsa, `preferAdapter` düşer ve eski bildirim +
  AppleScript yolu devralır. Çalışma zamanında olur, yeniden başlatma gerekmez.
- **İkililer bu depoda değil.** BSD-3-Clause artefaktları; `DynamicIsland/Vendor`
  içine konur, `tools/generate_pbxproj.py` onları `.app` paketine kopyalar.
  Derleme talimatı o klasörün README'sinde.
- Ayarlar → Modüller → **Sistem geneli medya** hangi yolun canlı olduğunu yazar.

### Sistem HUD'unu değiştirme

macOS ses/parlaklık HUD'unu `OSDUIHelper` ile çizer; kapatmanın desteklenen bir
yolu yok. HUD, tuşun window server'a **ulaşmasının sonucudur** — dolayısıyla tek
çare tuşu önce almak ve iletmemek. `CGEvent.tapCreate` (`.cghidEventTap`,
`.headInsertEventTap`) tam oraya oturur; callback'ten `nil` dönmek tuşu yutar,
sistem HUD'u hiç ateşlenmez ve seviyeyi ada kendi uygular.

- **Bedeli açıkça yazılı:** event tap **Erişilebilirlik** ister, bu yüzden modül
  varsayılan olarak **kapalı** — bildirim aynasıyla aynı kural.
- **Yutulan tuş mutlaka uygulanır.** İşleyici `false` dönerse tuş sisteme aynen
  geçirilir. Uygulanamayan bir tuşu yutmak, kullanıcıyı ses kontrolünden tümüyle
  etmek demektir — kaçınılan asıl hata bu. Klavye aydınlatma tuşları da bilerek
  bu "geçir" kümesinde: onları sürecek bir yolumuz yok.
- **Basma/bırakma eşleştirilir.** Yalnızca key-down'unu yuttuğumuz tuşun key-up'ı
  yutulur; eşleşmeyen bir bırakma sistemde ya takılı kalmış tuş ya da bastırdığımız
  HUD'un yine de görünmesi demek olurdu.
- **⇧⌥ hassas adım** macOS'taki gibi çeyrek adım hareket ettirir ve bu durumda %5
  ızgarası devreden çıkar — yoksa oturtma, kullanıcının istediği çeyrek adımı
  yutardı.

### Tam ekranda çekilme

Panel `.fullScreenAuxiliary`; bir ses HUD'u için doğru olan bu davranış, bir
filmin üstünde yanlış. Tam ekran bir uygulama adanın ekranını kullandığında panel
**tümüyle `orderOut` edilir** — saydam yapmak yetmez, görünmez bir pencere de
oynayan her karenin üstünde bileşimlenir.

Algılama izinsizdir: `CGWindowListCopyWindowInfo` katman 0'daki pencerelerin
sınırlarını ve sahibini izin istemeden verir (izin isteyen şey pencere
*başlıkları* ve *içeriği*, ikisi de okunmuyor). Space değişimi ve uygulama
etkinleşmesi dinlenir, ayrıca bunların ikisini de üretmeyen durum için (zaten önde
olan bir pencerede videonun tam ekrana geçmesi) 1 Hz'lik bir emniyet yoklaması var.

### Diğerleri

- **Genişletilmiş ada daraldı.** Ada üzerine geldiğinde *senin baktığın şeyin
  üstüne* açılıyor, yani yanlara aldığı her nokta başka bir pencerenin kapanan
  noktası. Payload genişlikleri olabilecek en geniş içeriğe göre ayarlanmıştı;
  olağan duruma göre yeniden ölçüldü: çalan parça **400 → 360**, geniş satırlar
  (güç / cihaz / bildirim / indirme) **380 → 360**, metre **320 → 300**, geri
  sayım **300 → 288**, hover çipleri **çip başına 78 → 74**. Uzun bir parça adı
  adayı genişleterek değil, marquee ile kaydırılarak çözülüyor.
- **Üst köşeler ters çevrildi.** Ada ekranın üst kenarıyla buluştuğu yerde içeri
  kıvrılıp bir sekme gibi bezelin *üstüne oturuyordu*. Artık tam tersi: köşeler
  dışa doğru açılıyor, yani ada üst kenarın genişlediği bir şey gibi okunuyor —
  donanım notch'unun kendi şekli bu, ve ekranın tepesindeki siyah bir dikdörtgeni
  "yapıştırılmış" görünmekten kurtaran şey de bu.
  - Kıvrımlar verilen dikdörtgenin **dışına** çiziliyor, her yandan tam olarak üst
    yarıçap kadar. Gövde böylece tam genişliğinde kalıyor — içeri çekilmiş bir
    gövde her payload'ı sessizce daraltırdı — ve taşan birkaç nokta panelin gölge
    payının rahatça içinde. O noktalar dekorasyon ve hit rect'in dışında kalıyor;
    doğrusu da bu, orada basılacak bir şey yok.
  - **Kompakt hâlde yarıçap sıfır**, yani kıvrımlar tümüyle kayboluyor: o pil
    fiziksel kesiğin *içinde* duruyor ve orada bir omuz, kameranın yanındaki menü
    çubuğuna siyah bulaştırmaktan başka bir işe yaramazdı — kompakt durumun gölge
    çizmemesiyle aynı gerekçe. Ada açıldıkça kıvrım büyüyor, çünkü asıl o zaman
    üzerine açılacak ekranı oluyor.
  - **Alt köşelere dokunulmadı**; onlar hâlâ dışbükey ve büyüdükçe açılan
    ifadeli köşeler.
- **Dalga formu albüm kapağının renklerini alıyor.** Kompakt pildeki dört çubuk
  artık kapağın **baskın renklerine** boyanıyor ve renk çubuklar boyunca
  geçiyor — dört ayrı renk değil, tek bir geçiş. Ortalama renk *değil*: kırmızı
  bir köşesi ve mavi bir zemini olan kapağın ortalaması, sleeve'de hiç
  bulunmayan çamurlu bir mor verir. Bunun yerine pikseller **tona göre 12 kovaya**
  bölünüyor, en dolu kovalar kazanıyor. Siyaha ve beyaza yakın pikseller ile
  soluk pikseller elenir (yoksa her kapak gri döner), kalan renk siyah pil
  üzerinde okunacak bir doygunluk/parlaklık tabanına çekilir. Kullanılabilir
  rengi olmayan bir kapak — siyah-beyaz fotoğraf, düz sleeve — **boş palet**
  döndürür ve çubuklar eskisi gibi beyaz kalır; ton uydurmak yerine eski
  görünüme düşmek doğru cevap. Sonuç parça başına bir kez hesaplanıp
  önbelleğe alınır (24×24'e küçültülmüş kapak, 576 piksel).

- **Ekran görüntüsü gizliliği.** `sharingType = .none` — parola alanlarının
  kullandığı anahtar. Ada ekran görüntüsünden, ekran kaydından ve paylaşılan
  ekrandan çıkar. Tercih olarak sunulur, dayatılmaz: toplantıda gizli istersin,
  hata raporu için çektiğin görüntüde görünsün istersin.
- **Kayan parça adı (marquee).** Ada en geniş hâlinde 400pt ve medya satırının
  çoğu kapak ile düğmelere gider; gerçek bir parça adı kesiliyordu. Metin
  sığmıyorsa kayar, sığıyorsa hiç kımıldamaz — çoğu ad kısadır ve sebepsiz
  kıpırdayan bir pil bozuk görünür. İki kopya arasında boşluk bırakılıp tam bir
  kopya kadar kaydırılır, böylece dikiş görünmez; iki uç adanın siyahına *mask*
  ile karışır (overlay değil — overlay siyahın üstüne gri leke çizerdi).
  - **Yerleşimi görünmez, kırpılan bir kopya sürer.** Kayan kopyalar gerçek
    genişliklerini korumak için `fixedSize` olmak zorunda, ama `fixedSize` aynı
    zamanda görünümün *asgari* genişliğini metnin tam genişliği yapar — ve bir
    yığın, katı bir çocuğa ne kadar az önerirse önersin onun asgarisini verir.
    Belirtisi sinsiydi: bir VStack'e konduğunda marquee kendi kabını metnin
    genişliği sanıp "sığıyor" diyor, hiç kaymıyor ve yanındaki her şeyi satırdan
    dışarı itiyordu — uzun bir parça adında albüm kapağı sola taşıyor, başlık
    transport tuşlarının altına giriyordu. Kırpan sıradan bir `Text`'in böyle bir
    asgarisi yok, dolayısıyla bileşen yeniden esnek ve nereye konursa konsun
    kendisine verilen genişliğe uyuyor.
  - Medya satırında metin sütunu ayrıca **açıkça hesaplanıyor**
    (`ExpandedMediaMetrics.textColumnWidth`), yığının çocuk ideallerinden
    türetmesine bırakılmıyor — dosyanın geri kalanı zaten böyle çalışıyor.
- **Pil olayları.** Fişe takma/çıkarmaya ek olarak **tam doldu** ve **düşük pil**
  (%20 / %10 / %5). Her eşik bir deşarj boyunca **bir kez** konuşur; IOKit eşiğin
  etrafında dakikalarca okuma yayınlar ve bunun bilançosu tutulmasa ada %20'yi
  tekrar tekrar duyururdu. %25'ten %3'e sert düşüşte en acil eşik konuşur, sonra
  geri tırmanıp %10'u anons etmez. Fişe takınca sayaç sıfırlanır.
- **Yarım kalmış indirmeler göstergeyi kilitlemiyor.** Kısmi dosyanın varlığı
  "iniyor" demek değil: tarayıcılar başarısız ya da iptal edilmiş indirmelerin
  dosyasını geride bırakıyor, ve İndirilenler'de unutulmuş tek bir `.download`
  paketi adada kalıcı bir indirme göstergesi bırakıyordu. Artık bir kısmi dosya
  yalnızca **büyüdüğü sürece** sayılıyor; birkaç saniye bayt kazanmayı keserse
  duraklamış sayılıyor. Uygulama açılırken klasörde zaten duran dosyalar da bu
  yüzden duraklamış başlıyor — onları bu oturum başlatmadı ve hareket ettiklerine
  dair bir kanıt yok. Duraklamış dosya varken yoklama 0,6 sn'den 5 sn'ye
  düşüyor, yani unutulmuş bir dosyanın maliyeti yok ama devam ettirilen bir
  indirme yine fark ediliyor — klasör izleyicisi tek başına görmez, çünkü o
  dosyaların belirip kaybolmasında tetiklenir, birine bayt eklenmesinde değil.
- **İndirme canlı etkinliği.** İndirilenler klasörü izlenir; her tarayıcı önce
  kısmi bir dosya yazıp bitince yerine taşır (`.crdownload`, `.part`,
  `.download`, `.opdownload`), yani bu dosyaların varlığı "iniyor", kaybolup
  yerine tam dosyanın gelmesi "bitti" demek. **Yüzde gösterilmez:** hiçbir tarayıcı
  beklenen toplam boyutu üçüncü bir uygulamanın okuyabileceği yerde yayınlamıyor;
  %90'a sürünüp orada takılan uydurma bir çubuk, dürüst bir bayt sayacından
  kötüdür. Yoklama yalnızca kısmi dosya varken çalışır, boşta maliyet sıfır.
- **Raftan geri sürükleme düzeltildi.** Bir dosyayı raftan dışarı sürüklemek
  çalışmıyordu, ve sebebi ilginçti: uygulama "biri dosya sürüklüyor" bilgisini
  **sistem sürükleme panosundan** çıkarıyor (bkz. `DragMonitor`) — ama
  `beginDraggingSession` bizim dosyamızı tam da o panoya yazıyor. Ada kendi
  başlattığı sürüklemeyi başkasınınki sanıp **bırakma alanına** dönüşüyor, raf
  çipleri kayboluyor ve kullanıcının dışarı çıkarmaya çalıştığı dosyayı adanın
  kendisi yakalıyordu. Görünümün kendi oturumu boyunca `isDraggingOut` bayrağı
  var artık: imleç örneklemesi o süre boyunca tümüyle duruyor (zaten fareyi
  AppKit yönetiyor) ve ada kendi dosyasını bırakma olarak kabul etmiyor —
  bir görünüm hem kaynak hem hedef olabildiği için AppKit dosyayı imleç adanın
  üstündeyken geri geri teklif ediyordu.
- **Albüm kapağına basmak parçanın geldiği uygulamayı öne getiriyor.** Hem
  **dinamik** hem **dinamik ada** hâlinde. MediaRemote yolundan gelen her şey
  için çalışır, yalnızca Music ve Spotify için değil: `.other` kaynağı gerçek
  paket kimliğini taşıdığı için tarayıcıda çalan bir parça o tarayıcıyı açar.
  İmleç üstündeyken kapak hafifçe aydınlanıyor, yoksa basılabilir olduğu
  anlaşılmıyordu.
- **Kompakt pil de yumuşak birleşiyor.** Üst kıvrım artık duruma değil
  **genişliğe** bakıyor: çıplak pil kesiğin içinde durduğu için yarıçap sıfır
  (orada bir omuz kameranın yanındaki menü çubuğuna siyah bulaştırırdı), ama bir
  aksesuar belirdiği anda pil kesiğin iki yanına taşıyor ve o omuzlar gerçek
  ekranda kalıyor — kare bırakılınca sert, düz bir birleşme gibi okunuyordu.
- **Takvim izni artık modül açılınca isteniyor.** Modülü açmak hiçbir şey
  sormuyordu: izin yoksa `refresh()` sessizce çıkıyor, ne uyarı ne etkinlik ne
  açıklama çıkıyordu — sistem uyarısını görmenin tek yolu Ayarlar'ın başka bir
  yerindeki ikinci bir düğmeyi bulmaktı. Artık modülü açmak **isteğin kendisi**;
  Now Playing'in Otomasyon için zaten izlediği kuralla aynı: izni gerçekten
  gerektiği anda iste. Menü çubuğu ajanı hiçbir zaman önde olmadığı için uygulama
  istek öncesi öne geliyor, yoksa sistem sayfası arkada açılabiliyor.
- **Raf 2.0.** ⌘/⇧-tıklama ile **çoklu seçim** (seçili çip halka ile
  işaretlenir, başlık kaçının seçili olduğunu yazar); alt satırdaki Copy /
  AirDrop / Clear seçim varsa seçime, yoksa rafın tamamına uygular. **Sağ tık
  menüsü:** Aç, Finder'da Göster, Kopyala, AirDrop, **Şuraya Taşı…**, Kaldır.
  Seçimin *içindeki* bir çipe sağ tıklamak menüyü tüm seçime uygular.
- **Taşı artık var.** Faz 4'te bilerek yapılmamıştı ("hedef sormadan taşımak
  veri kaybettirir"). Doğru olan hedefi sormaktı: `NSOpenPanel` ile klasör
  seçilir, çakışan ad Finder gibi "report 2.pdf" olur (asla üzerine yazılmaz) ve
  **yalnızca gerçekten taşınan** dosya raftan düşer — izin hatası alan bir dosya
  hem yerinde kalıp hem raftan silinemez.

---

## Dağıtım hedefi (Deployment target)

- **macOS 13.0 (Ventura) veya üzeri.**
- Yalnızca köklü, belgelenmiş API'ler kullanır: `NSScreen` safe-area/auxiliary
  API'leri (macOS 12+), `NSPanel`, `MenuBarExtra` (macOS 13+), SwiftUI
  `Settings` sahnesi ve `NSHostingView`. `SettingsLink` (macOS 14+) mevcut
  olduğunda kullanılır, macOS 13 için bir yedeği (fallback) vardır.

---

## Proje düzeni

```
dynamic_island_mac/
├── DynamicIsland/
│   ├── App/
│   │   ├── DynamicIslandApp.swift   @main App: MenuBarExtra + Settings sahnesi
│   │   ├── AppDelegate.swift        Katmanı oluşturur; paylaşılan durumu tutar
│   │   └── AppState.swift           Kalıcı ayarlar (UserDefaults)
│   ├── System/
│   │   ├── NotchDetector.swift      Fiziksel/simüle notch geometrisi
│   │   ├── OverlayPanel.swift       Kenarlıksız, etkinleştirmeyen NSPanel
│   │   ├── PassthroughHostingView.swift  Tıklama geçişi + AppKit tık yönlendirme
│   │   ├── VolumeMonitor.swift      CoreAudio ses/sessize alma dinleyicisi
│   │   ├── BrightnessMonitor.swift  DisplayServices (private) parlaklık okuma
│   │   ├── BatteryMonitor.swift     IOKit güç kaynağı bildirimleri
│   │   ├── NowPlayingMonitor.swift  Now Playing arbitrajı + transport komutları
│   │   ├── MediaRemoteAdapter.swift Sistem geneli Now Playing (perl köprüsü)
│   │   ├── MediaKeyMonitor.swift    Medya tuşu yakalama (sistem HUD'unu bastırır)
│   │   ├── FullscreenDetector.swift Tam ekran uygulama algılama
│   │   ├── DownloadMonitor.swift    İndirilenler klasörü canlı etkinliği
│   │   ├── BluetoothMonitor.swift   IO registry'den AirPods/kulaklık pili
│   │   ├── NotificationMonitor.swift Bildirim afişlerini AX ile okur
│   │   ├── CalendarMonitor.swift    Sıradaki etkinlik (EventKit)
│   │   ├── DragMonitor.swift        Uçuştaki dosya sürüklemesini yakalar
│   │   └── PrivacyMonitor.swift     Kamera/mikrofon kullanımda mı
│   ├── Island/
│   │   ├── IslandModel.swift        Etkileşim + içerik durumu, otomatik toplanma
│   │   ├── IslandPayload.swift      NowPlaying / PowerSnapshot / TransientKind
│   │   ├── IslandTimer.swift        Geri sayım (saatten türetilir)
│   │   ├── FileShelf.swift          Bırakılan dosyalar + kalıcılık
│   │   ├── IslandLayout.swift       Geometri için tek doğruluk kaynağı
│   │   └── IslandController.swift   Panel ⇄ model ⇄ ayarlar ⇄ izleyiciler
│   ├── UI/
│   │   ├── IslandView.swift         SwiftUI ada (üç durumun tümü)
│   │   ├── IslandPayloads.swift     HUD / Now Playing / Kontrol Merkezi içerikleri
│   │   ├── IslandComponents.swift   Metre, dalga formu, kapak, çip, SF Symbol seçimi
│   │   ├── MarqueeText.swift        Sığmayan metni kaydıran tek satır
│   │   ├── NotchShape.swift         Animasyonlanabilir üst/alt-yarıçap şekli
│   │   └── MenuBarView.swift        Durum çubuğu menü içeriği
│   ├── Settings/
│   │   └── SettingsView.swift       Ayarlar formu
│   ├── Vendor/                      Üçüncü taraf ikililer (normalde boş)
│   │   └── README.md                mediaremote-adapter nasıl derlenip konur
│   └── Resources/
│       ├── Info.plist               LSUIElement, kategori, sürümleme, simge
│       ├── AppIcon.icns             tools/make_icon.swift tarafından üretilir
│       └── DynamicIsland.entitlements  Sandbox KAPALI (aşağıya bakın)
├── DynamicIsland.xcodeproj/         Açılmaya hazır proje
│   ├── project.pbxproj              tools/generate_pbxproj.py tarafından üretilir
│   └── xcshareddata/xcschemes/DynamicIsland.xcscheme
└── tools/
    ├── generate_pbxproj.py          project.pbxproj'ü yeniden üretir (Xcode gerekmez)
    └── make_icon.swift              AppIcon.icns'i çizer
```

---

## Derleme ve Çalıştırma

**Xcode 15+** (macOS 13 SDK veya üzeri) olan bir Mac gerekir.

1. Xcode'da açmak için `DynamicIsland.xcodeproj` dosyasına **çift tıklayın**.
2. **`DynamicIsland`** şemasını (zaten paylaşılmış) ve bir **My Mac** hedefini
   seçin.
3. **⌘R** tuşlarına basın.

Uygulama bir menü çubuğu ajanı olduğundan (`LSUIElement`), **Dock simgesi ve ana
penceresi yoktur**. Başlatıldığında şunları görürsünüz:

- Menü çubuğunda **kapsül simgesi**.
- Ekranınızın üst-ortasında **ada pili** (notch'lu Mac'lerde notch üzerinde;
  aksi halde simüle bir pil). Notch'lu bir Mac'te kompakt ada kesiğin içinde
  durduğu için **görünmez** olması normaldir — üzerine gelin, açılacaktır.

> **Kod imzalama:** Hedef, "Sign to Run Locally" (ad-hoc) ile yapılandırıldı —
> yani hiçbir geliştirici hesabı veya takım seçmeden ⌘R çalışır. Dağıtıma
> geçerken hedef → *Signing & Capabilities* → *Team* seçip imzalamayı Automatic
> yapın (bkz. İzinler ve yetkiler: Developer ID + notarizasyon).

---

## Faz-1 davranışları nasıl test edilir

| Davranış            | Nasıl görülür |
|---------------------|---------------|
| **Kompakt pil**     | Varsayılan durum — notch'a yaslanan siyah bir pil. |
| **Hover → genişleme** | İşaretçiyi pilin üzerine getirin; yaylı bir şekilde genişletilmiş duruma açılır, ayrıldığınızda (otomatik toplanma gecikmesinden sonra) toplanır. |
| **Tıklama → Kontrol** | Adaya tıklayın; Kontrol Merkezi yer tutucusuna genişler. Kapatmak için tekrar tıklayın (veya menüyü kullanın). |
| **Demo genişletme** | Menü → **Demo: Expand Island** (ekran kaydı için pratik — hover gerekmez). |
| **Demo kontrol**    | Menü → **Demo: Show Control Center**. |
| **Zamanlayıcı**     | Menü → **Start Timer**, ya da Kontrol Merkezi'ndeki TIMER satırından bir ön ayar. Geri sayım notch'un yanında belirir. |
| **Dosya rafı**      | Bir dosyayı masaüstünden tutup notch'a doğru sürükleyin; ada bırakma alanına dönüşür. Bıraktıktan sonra Kontrol Merkezi'ndeki SHELF satırından geri sürükleyebilirsiniz. |
| **Ekran seçimi**    | Ayarlar → **Display**. Harici ekranda notch olmadığı için simüle pil çizilir. |
| **Ayarlar**         | Menü → **Settings…** (veya ⌘,). Ada boyutunu, animasyon hızını ve otomatik toplanma gecikmesini değiştirin ve adanın canlı tepkisini izleyin. |
| **Ekran değişiklikleri** | Çözünürlüğü değiştirin ya da bir ekran takıp çıkarın; katman yeniden hesaplanıp konumlanır. |

---

## Xcode projesini yeniden üretme

`.xcodeproj` commit edilmiştir, böylece doğrudan açabilirsiniz. Eğer bir gün
yeniden üretmeniz gerekirse (örneğin Swift dosyaları ekledikten sonra), şu iki
yaklaşımdan **birini** kullanın:

```bash
python3 tools/generate_pbxproj.py
```
Bu, `DynamicIsland/{App,System,Island,UI,Settings}` altındaki Swift dosyalarını
tarar ve `DynamicIsland.xcodeproj/project.pbxproj` dosyasını yeniden yazar.
UUID'ler belirlenimci (deterministic) olduğundan diff temiz kalır.

> Xcode'un kendi "Add Files…" akışını kullanırsanız buna gerek yok. Dosyayı
> doğrudan Finder'dan bir grup klasörüne kopyaladıysanız, derlemeye dahil olması
> için yukarıdakini çalıştırın.

---

## İzinler ve yetkiler (entitlements)

> Faz 6 notu: aşağıdaki "tek izin" cümlesi artık iki koşula bağlı. **Otomasyon**
> yalnızca MediaRemote adapter'ı *yokken* gerekir (varken hiçbir izin gerekmez).
> **Erişilebilirlik** ise iki isteğe bağlı modülün koşulu: bildirim aynası ve
> medya tuşu yakalama. İkisi de varsayılan olarak kapalıdır ve macOS izni
> özelliğe değil sürece verir — yani bir kez verilir, ikisi de kullanır.

- **Tek izin: Otomasyon (Automation).** Yalnızca Now Playing modülü içindir ve
  ilk kullanımda macOS sorar ("Dynamic Island, Music'i kontrol etmek istiyor").
  Reddedilirse yalnızca o modül sessizleşir, başka hiçbir şey bozulmaz. Gerekçe
  `Info.plist` içindeki `NSAppleEventsUsageDescription`'da yazılıdır.
  Music/Spotify **zaten çalışmıyorsa hiç sorgulanmaz**, dolayısıyla kullanmadığın
  bir oynatıcı için izin istenmez.
- **Accessibility, Ekran Kaydı, Girdi İzleme: hiçbiri gerekmez.** Hover, olay
  yakalamayla değil `NSEvent.mouseLocation` ile okunur — bu düz bir geometri
  sorgusu olduğundan izin istemez.
- **Her şey yerelde işlenir.** Hiçbir veri dışarı gönderilmez. Tek ağ isteği,
  Spotify'ın verdiği albüm kapağı URL'sinin indirilmesidir.
- ⚠️ **Bir private API kullanılır:** parlaklık okuması için
  `DisplayServices.DisplayServicesGetBrightness`. macOS'ta yerleşik ekranın
  parlaklık seviyesini okumanın desteklenen bir yolu yok (IOKit yolu Apple
  Silicon'da çalışmıyor). `dlopen`/`dlsym` ile dinamik yüklenir; sembol
  bulunamazsa modül kendini kapatır, uygulama çökmez. Bu, App Store'u
  dışlar — zaten sandbox'sız olduğu için dışlanmış durumda.
- **App Sandbox bilinçli olarak KAPALIDIR** (`DynamicIsland.entitlements`). Her
  Space'te sürekli en üstte kalan, sistem geneli bir katman sandbox'a doğal
  olarak uymaz ve sonraki fazların sistem durumunu (medya, bildirimler,
  zamanlayıcılar) gözlemlemesi beklenir. Sonuçları:
  - Uygulama **Mac App Store**'da yayınlanamaz; **Developer ID + notarizasyon**
    ile dağıtılır.
  - **Hardened Runtime ETKİN kalır** (derleme ayarı); bu, sandbox'sız bir
    uygulamayla uyumludur ve notarizasyon için gereklidir.
- **Sonraki fazlar**, kamera/mikrofon göstergeleri ve bildirimler geldikçe ek
  izinler isteyebilir. Faz 2'de bunların hiçbiri bağlı değildir.

---

## Uygulama adı ve simgesi

Paket **`Dinamik Ada.app`** adıyla üretilir; Finder, Launchpad ve Spotlight bunu
gösterir. Hedef, kaynak klasörü, şema ve bütün yollar `DynamicIsland` olarak
kalır — görünen ad `DISPLAY_NAME` ile ayrı tutulduğu için ürünü yeniden
adlandırmak projeyi karıştırmaz. **Paket kimliği de değişmez**
(`com.abacusisland.dynamicisland`), yani ayarlar ve verilmiş izinler eski
kurulumdan taşınır.

Simge bir ikili olarak commit edilmez, **çizilir**:

```bash
swift tools/make_icon.swift
```

Bu, `DynamicIsland/Resources/AppIcon.icns` dosyasını on boyutuyla birlikte
üretir; `Info.plist` içindeki `CFBundleIconFile` onu gösterir ve
`tools/generate_pbxproj.py` paketin Resources'ına kopyalar. Gerekçe
`generate_pbxproj.py` ile aynı: sayıları düzenleyerek ayarlanabilsin.

Ne çizdiği: uygulamanın konusu notch olduğu için simge de notch. Ada, çerçevenin
üst kenarına yapışık duruyor — ters kıvrımlar ancak kaynaşacak bir kenarları
olduğunda bir anlam ifade eder; boşlukta asılı kaldıklarında hiçbir şeye kıvrılır
ve şekil "notch" değil "siyah kutu" gibi okunur. İçindeki dört çubuk kompakt
pilin çaldığı sırada gösterdiği çubukların aynısı.

Renkler tonun etrafından harmanlanıyor, düz RGB'den değil: turkuazdan pembeye
düz interpolasyon griden geçiyor ve ortadaki iki çubuk soluk çıkıyordu. Ton
üzerinden geçince her adım doygun kalıyor — turkuaz, mavi, mor, pembe.

Her ölçü tuvalin bir kesri olarak yazıldığı için 16pt sürümü 1024pt sürümünün
aynısıdır, ayrı bir çizim değil. Tek istisna adanın çevresindeki saç teli: 16pt'de
yarım noktalık bir çizgi arka plana karışacağı için yalnızca görülebildiği
boyutlarda çiziliyor.

---

## Bilinen sınırlamalar

- **Tarayıcı medyası, kapak/düğme izni ve önceden başlamış çalma** — bu üçü
  Faz 6'da `mediaremote-adapter` ile çözüldü, **ama yalnızca adapter ikilileri
  `DynamicIsland/Vendor` içine konduğunda.** Konmadığında (temiz bir klonun
  normal hâli) üçü de aynen geçerli: Now Playing yalnızca Music ve Spotify'ı
  görür, kapak ile transport düğmeleri Otomasyon ister ve uygulamadan önce
  başlamış bir çalma bir sonraki değişime kadar görünmez. Hangi yolun canlı
  olduğu Ayarlar → **Sistem geneli medya** satırında yazar.
- **Parlaklık yoklanır (poll).** Değişimi bildiren bir API yok, saniyede 4 kez
  okunur. Okuma ucuz bir C çağrısı olduğundan ölçülebilir bir yük getirmez.
- **Parlaklık private API'ye bağlı** (yukarıya bakın); gelecekte bir macOS
  sürümünde sessizce devre dışı kalabilir.
- **Serbest süreli zamanlayıcı adadan girilemez.** Panel klavye odağı alamadığı
  için ada üç ön ayar sunar; tam liste menü çubuğundadır.
- **Pil bilgisi cihazın yayınlamasına bağlıdır.** AirPods ve çoğu Beats yayınlar;
  jenerik Bluetooth kulaklıkların bir kısmı yayınlamaz ve o zaman gösterilmez.
- **macOS Saat uygulamasının zamanlayıcıları okunamaz.** Adanın zamanlayıcısı
  kendi zamanlayıcısıdır; Saat'ten ya da Siri'den başlatılan bir sayaç adada
  görünmez. Bunu sağlayacak API (`MTTimerManager`) var ve yüklenebiliyor, ancak
  `mobiletimerd` üçüncü taraf bir sürece hizmet vermiyor: `timersSync` ve
  `getCurrentTimerSync` daima `nil` dönüyor, zamanlayıcı başlatma sessizce hiçbir
  şey yapmıyor — yetki korumalı. "Çalışıyor gibi görünüp hiç ateşlenmeyen" bir
  entegrasyon yazmamak için bu yol bilinçli olarak kapalı bırakıldı.
- **Tarayıcı sekmesinin kamerayı kullanması** kamera göstergesini tetikler, ancak
  hangi uygulamanın kullandığı gösterilmez — bu bilgi izin gerektirir.
- **Bildirimler Erişilebilirlik ister.** Bildirim Merkezi'nin veritabanı
  (`group.com.apple.usernoted/db2/db`) Full Disk Access olmadan okunamıyor
  (ölçüldü: erişim reddedildi) ve özel bir SQLite şeması olduğu için her macOS
  sürümünde kırılabilir. Kalan yol afişi *çizildiği hâliyle* AX ile okumak;
  modül bunu yapar ve bu yüzden varsayılan olarak kapalıdır. Hiçbir şey saklanmaz.
- **Medya tuşlarını devralmak Erişilebilirlik ister** ve bu yüzden varsayılan
  olarak kapalıdır. İzin verilmezse sistemin kendi HUD'u adanınkiyle yan yana
  görünmeye devam eder — bastırmanın başka bir yolu yok.
- **Klavye aydınlatma tuşları devralınmaz.** Yakalanabilirler ama arkalarındaki
  aydınlatmayı sürecek bir API yok; yutup uygulayamamak tuşu tümden bozardı.
- **Tam ekran algılama pencere sınırına bakar.** Ekranı tam kaplayan katman-0 bir
  pencere tam ekran sayılır. Kendini bilerek ekran boyutunda konumlandıran
  kenarlıksız bir uygulama da bu tanıma girer; `Ayarlar → Davranış`'tan kapatılabilir.
- **Tam ekran algılama boşta ~0,8 puan CPU'ya mal oluyor.** İki saniyede bir
  ekrandaki pencerelerin listesi okunuyor; bunun daha ucuz bir genel API'si yok.
  Ölçüm yukarıda; rahatsız ediyorsa `Ayarlar → Davranış → Tam ekranda gizle`
  kapatılır.
- **İndirmede yüzde yok.** Hiçbir tarayıcı beklenen toplam boyutu üçüncü bir
  uygulamanın okuyabileceği yerde yayınlamıyor (Chrome kendi veritabanında
  tutuyor, Safari'nin `.download`'u kapalı bir paket). Bayt sayacı doğru, uydurma
  bir çubuk olmazdı.
- **Çoklu ekran:** katman, varsa dahili notch'lu ekranı hedefler, aksi halde ana
  ekranı. Ekran başına ada ve ekran seçimi sonraki bir fazın konusudur.
- `matchedGeometryEffect` kullanılmaz (durumlar çerçevelerini çapraz-solma + yay
  ile geçirir); öğe düzeyinde süreklilik için sonradan eklenebilir.

---

## Lisans

MIT — bkz. [LICENSE](LICENSE).

Üçüncü taraf: sistem geneli Now Playing için isteğe bağlı olarak kullanılan
[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
**BSD-3-Clause** ile dağıtılıyor. İkilileri bu depoda değil; `DynamicIsland/Vendor`
içine koyarsan lisans metnini de yanına koy.

---

## Yol haritası (sonraki fazlar — henüz bu depoda değil)

- **Developer ID imzalama + notarize dağıtım.** Bu makinede geçerli imzalama
  kimliği yok, dolayısıyla **Sparkle otomatik güncelleme bilerek ertelendi**:
  imzalanmamış ve notarize edilmemiş bir güncellemeyi Gatekeeper zaten
  açtırmaz, o hâlde çalışmayan bir "Güncellemeleri Denetle" düğmesi bırakmanın
  anlamı yok. İmza geldiğinde Sparkle + appcast tek adım.
- **Ekran başına ada.** Katman şu an tek ekran hedefler; ekran tercihi var,
  aynı anda birden fazla ada yok.
- **Söz (lyrics)** ve genel cilalama. (Uygulama simgesi yapıldı.)
