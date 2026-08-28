# BOOX Send

Mac’inizde bir dosyaya sağ tıklayıp **Hızlı İşlemler → BOOX’a Gönder** diyerek
dosyayı internet, bulut veya kablo kullanmadan Bluetooth üzerinden BOOX Go 10.3
cihazının `Books` klasörüne gönderin.

> Bu proje gerçek bir ihtiyaçtan doğdu: Mac’ten BOOX’a tek seferlik dosya
> göndermek gereksiz derecede zahmetliydi. Yapay zekâ destekli **vibe coding**
> yaklaşımıyla, gerçek cihaz üzerinde denenerek geliştirildi. Aynı ihtiyacı olan
> insanlarla ücretsiz ve açık kaynak olarak paylaşılmak isteniyor. Kodun önemli
> dosyalarda kullanılmadan önce gözden geçirilmesi ve test edilmesi önerilir.

[English README](../README.md) · [Kurulum](INSTALL.md) ·
[Değişiklikler](../CHANGELOG.md) · [Katkıda bulunma](../CONTRIBUTING.md)

## Neler yapar?

- Finder’da tek veya birden fazla dosya için sağ tık menüsü ekler.
- Dosyaları yalnızca eşleştirilmiş Mac ile BOOX arasında Bluetooth RFCOMM
  üzerinden taşır; sunucu veya hesap gerekmez.
- BOOX yeniden başladıktan sonra alıcıyı otomatik açar; Android Companion Device
  olayı da ek uyandırma yolu olarak kullanılır.
- Aktarım kesilirse aynı kuyruk işi kaldığı yerden devam edebilir.
- Dosya boyutunu ve SHA-256 özetini doğrular.
- Aynı adlı dosyaları ezmek yerine `dosya (1).pdf` biçiminde adlandırır.
- RFCOMM bağlantısını bloklayarak bekler; sürekli tarama, zamanlayıcı veya
  periyodik yenileme yapmaz.

Bu bir klasör eşitleme uygulaması değildir. Mac’ten silinen dosyaları BOOX’tan
silmez; yalnızca kullanıcının açıkça seçtiği dosyaları gönderir.

## Nasıl çalışır?

```text
Finder Hızlı İşlemi
        ↓
Mac'teki yerel dosya kuyruğu
        ↓  Bluetooth Classic / SDP + RFCOMM
BOOX açılışı veya Android Companion Device olayı
        ↓
Bloklayan RFCOMM dinleyicisi
        ↓
BOOX Books klasörü + SHA-256 doğrulaması
```

1. Finder Hızlı İşlemi seçilen dosyaları Mac’teki yerel kuyruğa kopyalar ve
   menü çubuğu uygulamasını haberdar eder.
2. Mac yalnızca önceden eşleştirilmiş BOOX’a bağlanır. Hizmet keşfi için SDP,
   dosya akışı için **Bluetooth Classic BR/EDR üzerinde RFCOMM** kullanılır.
   RFCOMM, seri bağlantı benzeri, bağlantı odaklı bir byte akışıdır; BLE/GATT
   veya internet kullanılmaz. Android’in RFCOMM açıklaması için
   [`BluetoothServerSocket` belgesine](https://developer.android.com/reference/android/bluetooth/BluetoothServerSocket)
   bakabilirsiniz.
3. BOOX’ta Android’in Companion Device association’ı Mac’in varlık olayını
   uygulamaya iletir. Bu association tek başına bağlantı kurmaz veya sürekli
   uygulama taraması başlatmaz; yalnızca işletim sisteminin uygulamayı olay
   geldiğinde uyandırabilmesini sağlar. Ayrıntı:
   [Android Companion Device](https://developer.android.com/develop/connectivity/bluetooth/companion-device-pairing).
4. BOOX açıldığında RFCOMM dinleyicisi otomatik başlar. Companion Device olayı
   da ek uyandırma yolu sağlar. Dinleyici `accept()` içinde bloklanır; tarama ya
   da periyodik uyanma yapmaz. Uygulama elle açılırsa yedek olarak düşük
   öncelikli bir `connectedDevice` foreground service'e yükseltilir.
5. Dosya boyutu ve SHA-256 özeti doğrulandıktan sonra aktarım tamamlanır ve
   dinleyici bir sonraki bağlantıyı bekler.

## Pil kullanımı

- Uygulama seviyesinde periyodik Bluetooth taraması yoktur.
- `WorkManager`, zamanlanmış job, alarm, timer veya yenileme döngüsü yoktur.
- Reset sonrasında güvenilir teslimat için Bluetooth açıkken normal bir arka
  plan servisi ve bloklayan RFCOMM sunucu soketi açık kalır.
- Bloklayan `accept()` çağrısı polling yapmaz ve CPU'yu sürekli çalıştırmaz;
  yine de bellekte kalan süreç ve açık soketin küçük bir boşta tüketimi olabilir.
- Uygulama elle açıldığında yedek foreground modu kullanılır. Resmî arka plan
  önerileri:
  [Android Bluetooth background guide](https://developer.android.com/develop/connectivity/bluetooth/ble/background).

Bu tasarım polling yapan bir uygulamadan daha sakindir ancak “sıfır pil
tüketimi” anlamına gelmez. BOOX’ta Bluetooth’un açık tutulmasının firmware ve
radyo kaynaklı taban tüketimi de vardır. Henüz kontrollü, çok günlük bir pil
benchmark’ı yayımlanmadığı için kesin yüzde tasarruf iddiasında bulunmuyoruz.

## Destek durumu

- Donanım üzerinde doğrulandı: **BOOX Go 10.3 / Android 12 tabanlı firmware**.
- Mac gereksinimi: **macOS 14 veya yenisi**, Bluetooth ve Apple Silicon ya da
  Intel işlemci.
- Diğer Android 12+ BOOX modellerinde çalışabilir ancak henüz doğrulanmamıştır.
- BOOX tamamen kapalıysa Bluetooth ile açılamaz. Cihaz açık veya uyku halinde,
  Bluetooth etkin olmalıdır.

## Ücretli imza olmadan dağıtım

İki platformun durumu farklıdır:

- **Android/BOOX:** Ücretli hesap gerekmez. Android APK’ları imzalı olmak
  zorundadır ama bu anahtar ücretsiz olarak `keytool` ile üretilebilir. GitHub
  Actions aynı özel anahtarı secret olarak kullanır; böylece sonraki sürümler
  mevcut uygulamanın üzerine güncelleme olarak kurulabilir. Anahtar depoya
  eklenmez ve kaybedilmemelidir.
- **macOS:** Apple’ın tanıdığı Developer ID imzası ve noterleme ücretli Apple
  Developer üyeliği gerektirir. Üyelik olmadan önerilen ücretsiz yöntem,
  kullanıcının kaynak koddan `./scripts/install-macos.sh` çalıştırıp uygulamayı
  kendi Mac’inde oluşturmasıdır. Hazır ad-hoc imzalı ZIP de kullanılabilir ancak
  macOS ilk açılışta uyarı gösterebilir; kullanıcı yalnızca kaynağa güveniyorsa
  **Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç** yolunu kullanmalıdır.
  Apple’ın açıklaması: [bilinmeyen geliştiriciden uygulama açma](https://support.apple.com/guide/mac-help/mh40616/mac).

Bu proje ücretli sertifika olmadan tamamen kullanılabilir. Ücretli Apple
sertifikası yalnızca hazır Mac paketini daha pürüzsüz ve doğrulanabilir hâle
getirir; kaynak koddan kurulumu veya Bluetooth aktarımını açan bir lisans
değildir.

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
`adb` gerekir. Ayrıntılar ve sorun giderme için [kurulum rehberine](INSTALL.md)
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

Daha fazla bilgi: [SECURITY.md](../SECURITY.md) ve [protokol tanımı](../protocol/SPEC.md).

## Kaldırma

```sh
./scripts/uninstall-macos.sh          # uygulamayı kaldır, kuyruk/ayarları koru
./scripts/uninstall-macos.sh --purge  # kuyruk ve ayarları da Çöp'e taşı
./scripts/uninstall-boox.sh           # BOOX uygulamasını ADB ile kaldır
```

Gönderilmiş kitaplar kaldırma sırasında silinmez.

## Lisans

[MIT](../LICENSE). Bu proje ONYX/BOOX veya Apple tarafından geliştirilmemiştir ve
bu şirketlerle bağlantılı değildir. “BOOX” ilgili sahibinin ticari markasıdır.
