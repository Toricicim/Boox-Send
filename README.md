# BOOX Send

Mac’inizde bir dosyaya sağ tıklayıp **Hızlı İşlemler → BOOX’a Gönder** diyerek
dosyayı internet, bulut veya kablo kullanmadan Bluetooth üzerinden BOOX Go 10.3
cihazının `Books` klasörüne gönderin.

> Bu proje gerçek bir ihtiyaçtan doğdu: Mac’ten BOOX’a tek seferlik dosya
> göndermek gereksiz derecede zahmetliydi. Yapay zekâ destekli **vibe coding**
> yaklaşımıyla, gerçek cihaz üzerinde denenerek geliştirildi. Aynı ihtiyacı olan
> insanlarla ücretsiz ve açık kaynak olarak paylaşılmak isteniyor. Kodun önemli
> dosyalarda kullanılmadan önce gözden geçirilmesi ve test edilmesi önerilir.

[English README](docs/README.en.md) · [Kurulum](docs/INSTALL.md) ·
[Değişiklikler](CHANGELOG.md) · [Katkıda bulunma](CONTRIBUTING.md)

## Neler yapar?

- Finder’da tek veya birden fazla dosya için sağ tık menüsü ekler.
- Dosyaları yalnızca eşleştirilmiş Mac ile BOOX arasında Bluetooth RFCOMM
  üzerinden taşır; sunucu veya hesap gerekmez.
- BOOX uygulaması kapalıyken Android Companion Device olayıyla kısa süreliğine
  uyanabilir.
- Aktarım kesilirse aynı kuyruk işi kaldığı yerden devam edebilir.
- Dosya boyutunu ve SHA-256 özetini doğrular.
- Aynı adlı dosyaları ezmek yerine `dosya (1).pdf` biçiminde adlandırır.
- Son bağlantıdan sonra 15 saniye boşta kalan BOOX alıcısını kapatır; sürekli
  tarama, zamanlayıcı veya periyodik yenileme yapmaz.

Bu bir klasör eşitleme uygulaması değildir. Mac’ten silinen dosyaları BOOX’tan
silmez; yalnızca kullanıcının açıkça seçtiği dosyaları gönderir.

## Destek durumu

- Donanım üzerinde doğrulandı: **BOOX Go 10.3 / Android 12 tabanlı firmware**.
- Mac gereksinimi: **macOS 14 veya yenisi**, Bluetooth ve Apple Silicon ya da
  Intel işlemci.
- Diğer Android 12+ BOOX modellerinde çalışabilir ancak henüz doğrulanmamıştır.
- BOOX tamamen kapalıysa Bluetooth ile açılamaz. Cihaz açık veya uyku halinde,
  Bluetooth etkin olmalıdır.

## En kolay kurulum

### GitHub sürüm paketinden

1. GitHub’daki **Releases** sayfasından macOS ZIP dosyasını ve Android APK’yı
   indirin.
2. ZIP’i açıp `Install.command` dosyasına çift tıklayın. Apple imzasız bir test
   sürümünde macOS engellerse dosyaya sağ tıklayıp **Aç** seçeneğini kullanın.
3. APK’yı BOOX’a kopyalayıp açın veya USB hata ayıklama ile kurun:

   ```sh
   adb install -r BOOX-Send-android.apk
   ```

### Kaynak koddan tek komutla

Önce macOS’ta Xcode Command Line Tools’u kurun:

```sh
xcode-select --install
```

Depoyu indirdikten sonra:

```sh
./scripts/install.sh
```

Bu komut Mac uygulamasını ve Finder Hızlı İşlemini kurar. BOOX USB hata ayıklama
ile bağlıysa Android uygulamasını da derleyip yükler. Yalnızca bir tarafı kurmak
için:

```sh
./scripts/install-macos.sh
./scripts/install-boox.sh
```

Android tarafını kaynak koddan kurmak için ayrıca JDK 17+, Android SDK 35 ve
`adb` gerekir. Ayrıntılar ve sorun giderme için [kurulum rehberine](docs/INSTALL.md)
bakın.

## İlk kurulum

1. Mac ve BOOX’u sistem Bluetooth ayarlarından normal şekilde eşleştirin.
2. Mac’in menü çubuğundaki **BOOX** simgesinden Ayarlar’ı açın, eşleştirilmiş
   BOOX’u seçin ve sekiz karakterli bir kod üretin.
3. BOOX’ta BOOX Send’i açın, aynı kodu kaydedin.
4. **Hedef Klasörü Seç** ile `Books` klasörünü seçin.
5. **Mac’i Companion Cihaz Olarak Eşleştir** düğmesine basıp Mac’i seçin.
6. BOOX uygulama ayarlarında Freeze’i kapatıp App Startup’ı açın. Uygulamanın
   sürekli çalışan bir tarayıcısı yoktur.

Artık Finder’da dosyaya sağ tıklayıp **Hızlı İşlemler → BOOX’a Gönder**
seçeneğini kullanabilirsiniz. BOOX ulaşılamıyorsa dosya Mac kuyruğunda kalır;
menü çubuğundan **Tekrar Dene** seçilebilir.

## Geliştirme

```sh
make check          # kaynak kontrolleri ve testler
make build-macos    # yerel mimari için Mac uygulaması
make build-android  # debug APK
make package        # Apple Silicon + Intel macOS yayın ZIP'i
```

Mac’in imzalı Finder extension hedefi XcodeGen projesinde korunmaktadır. Yerel
ve açık kaynak kurulum, ücretli Apple Developer sertifikası gerektirmemek için
daha güvenilir olan Automator Quick Action’ı kullanır.

Docker ana kurulum yöntemi değildir: macOS uygulama imzası, Finder servisi,
IOBluetooth ve fiziksel USB/ADB erişimi bir Linux konteynerinden sağlanamaz.
Tekrarlanabilir kontroller GitHub Actions üzerinde çalışır.

## Gizlilik ve güvenlik

- Bulut, telemetri, analiz veya kullanıcı hesabı yoktur.
- Sekiz karakterli kod uygulama protokolünü HMAC-SHA256 ile doğrular.
- İçerik uygulama katmanında ayrıca şifrelenmez; eşleştirilmiş Bluetooth
  bağlantısının güvenliğine dayanır.
- Dosyalar aktarım sonunda SHA-256 ile doğrulanır.
- İmzalama anahtarlarını ve kurulum kodlarını depoya eklemeyin.

Daha fazla bilgi: [SECURITY.md](SECURITY.md) ve [protokol tanımı](protocol/SPEC.md).

## Kaldırma

```sh
./scripts/uninstall-macos.sh          # uygulamayı kaldır, kuyruk/ayarları koru
./scripts/uninstall-macos.sh --purge  # kuyruk ve ayarları da Çöp'e taşı
./scripts/uninstall-boox.sh           # BOOX uygulamasını ADB ile kaldır
```

Gönderilmiş kitaplar kaldırma sırasında silinmez.

## Lisans

[MIT](LICENSE). Bu proje ONYX/BOOX veya Apple tarafından geliştirilmemiştir ve
bu şirketlerle bağlantılı değildir. “BOOX” ilgili sahibinin ticari markasıdır.
