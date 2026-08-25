# Kurulum ve sorun giderme

## Hazır sürüm paketi

### Mac

1. `BOOX-Send-<sürüm>-macOS-universal.zip` dosyasını açın.
2. `Install.command` dosyasına çift tıklayın.
3. İstenirse yönetici parolanızı girin; uygulama `/Applications` altına,
   Finder Hızlı İşlemi `~/Library/Services` altına kurulur.
4. Apple tarafından noterlenmemiş bir geliştirme sürümünde macOS engeli çıkarsa
   `Install.command` dosyasına sağ tıklayıp **Aç** deyin. Tanımadığınız bir
   kaynaktan gelen pakette Gatekeeper’ı devre dışı bırakmayın.

### BOOX

APK dosyasını BOOX’a kopyalayıp dosya yöneticisinden açabilir veya Android
Platform Tools ile kurabilirsiniz:

```sh
adb devices
adb install -r BOOX-Send-android.apk
```

BOOX’ta **Ayarlar → Sistem Ayarları → Geliştirici seçenekleri → USB hata
ayıklama** açık olmalıdır. Menü görünmüyorsa **Cihaz hakkında → Yapım numarası**
alanına birkaç kez dokunarak geliştirici seçeneklerini etkinleştirin.

## Kaynak koddan kurulum

Gereksinimler:

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`)
- Android için JDK 17+, Android SDK 35 ve Platform Tools/`adb`
- İlk indirmede Gradle bağımlılıkları için internet erişimi

Komutlar:

```sh
./scripts/install-macos.sh
./scripts/install-boox.sh
```

Mac betiği çalıştığı mimariyi derler. Yayın paketi betiği Apple Silicon ve Intel
dilimlerini birleştirerek evrensel uygulama oluşturur.

## Finder menüsü görünmüyor

1. Normal bir dosyaya sağ tıkladığınızdan emin olun; klasör seçmek desteklenmez.
2. **Hızlı İşlemler** alt menüsünü kontrol edin.
3. **Sistem Ayarları → Genel → Giriş Öğeleri ve Genişletmeler → Finder** altında
   `BOOX’a Gönder` seçeneğini açın.
4. Aşağıdaki komutla servisi yeniden kaydedin:

   ```sh
   /System/Library/CoreServices/pbs -flush
   /System/Library/CoreServices/pbs -update
   ```

5. Gerekirse Finder’ı kapatıp yeniden açın veya oturumu kapatıp açın.

## BOOX uyanmıyor veya aktarım başlamıyor

- İki cihazın Bluetooth ayarlarında birbirine eşleştirilmiş olduğunu kontrol
  edin.
- Mac uygulamasındaki BOOX adresi ile BOOX’taki Companion association aynı
  cihazları göstermelidir.
- Sekiz karakterli kod iki tarafta birebir aynı olmalıdır.
- BOOX’ta uygulama Freeze kapalı, App Startup açık olmalıdır.
- Cihaz tamamen kapalıysa Bluetooth onu açamaz. Otomatik kapanmayı kapatın.
- İlk association sırasında konum hizmetlerinin geçici olarak açık olması bazı
  BOOX firmware sürümlerinde gerekebilir; uygulama konum verisi istemez.

## Kuyruk ve tekrar deneme

Başarısız işler `~/Library/Application Support/BOOX Send/Queue` altında tutulur.
Mac menü çubuğundaki **BOOX → Tekrar Dene** ile yeniden gönderilir. `--purge`
seçenekli kaldırma dışında kurulum güncellemesi bu kuyruğu korur.

## Log toplama

Mac:

```sh
log stream --predicate 'subsystem == "com.aliumutaltas.BooxSend"'
```

BOOX:

```sh
adb logcat -s BooxSend
adb shell dumpsys activity services com.aliumutaltas.booxsend
```

Hata raporuna kurulum kodu, Bluetooth adresi veya özel dosya içeriği eklemeyin.
