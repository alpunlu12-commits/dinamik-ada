# Vendor

Üçüncü taraf ikili dosyalar burada durur. Bu klasör **normalde boştur**; içine
bir şey koyulmadığında proje aynen eskisi gibi üretilir ve uygulama sorunsuz
derlenir.

---

## mediaremote-adapter — sistem geneli Now Playing

Buraya iki şey konur:

```
DynamicIsland/Vendor/MediaRemoteAdapter.framework
DynamicIsland/Vendor/mediaremote-adapter.pl
```

`python3 tools/generate_pbxproj.py` bunları görür ve `.app` paketinin
`Contents/Resources/` klasörüne olduğu gibi kopyalar. `MediaRemoteAdapter.swift`
oradan okur.

### Neden gerekli

macOS'ta sistem geneli "çalan parça" kaydı — medya tuşlarının, Kontrol
Merkezi'nin ve Kilit Ekranı'nın okuduğu kayıt — özel `MediaRemote` framework'ünde
durur ve **her şeyi** görür: Safari, Chrome, YouTube, VLC, IINA, Podcasts.
macOS 15.4'te Apple bu framework'ü paket kimliği `com.apple.` ile başlayan
proseslerle sınırladı.

`/usr/bin/perl` bir Apple ikilisidir ve paket kimliği `com.apple.perl5`'tir —
yani bu kontrolü geçer. Adapter, framework'ü Perl prosesinin içine yükler,
MediaRemote ile orada konuşur ve sonucu stdout'a JSON satırları olarak yazar.
Bu uygulamaya hiçbir özel API linklenmez.

### Nasıl derlenir

```bash
brew install cmake
git clone https://github.com/ungive/mediaremote-adapter.git
cd mediaremote-adapter
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

Derleme bitince `MediaRemoteAdapter.framework` ve `mediaremote-adapter.pl`
dosyalarını bu klasöre kopyala, sonra:

```bash
python3 tools/generate_pbxproj.py
```

Doğrulamak için (uygulamayı çalıştırmadan):

```bash
/usr/bin/perl DynamicIsland/Vendor/mediaremote-adapter.pl \
  DynamicIsland/Vendor/MediaRemoteAdapter.framework get
```

Bir şey çalarken bu komut JSON basmalı. `null` basıyorsa gerçekten bir şey
çalmıyordur; hata veriyorsa framework mimarisi (arm64 / x86_64) uyuşmuyordur.

### Yoksa ne olur

`MediaRemoteAdapter.isAvailable` false olur, `NowPlayingMonitor` hiç denemez ve
mevcut yola düşer: Music + Spotify'ın yayınladığı dağıtık bildirimler, kapak ve
düğmeler için Otomasyon izni. Yani tarayıcı medyası ve ilerleme çubuğu olmaz,
başka hiçbir şey değişmez.

### Lisans

mediaremote-adapter **BSD-3-Clause** ile dağıtılıyor. İkilileri bu depoya commit
edeceksen lisans metnini de yanına koy.
