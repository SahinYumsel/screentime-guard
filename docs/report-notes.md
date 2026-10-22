# Rapor ve Sunum Notları (`screentime-guard`)

Bu doküman, **Mobil Teknolojiler** dersi tesliminde istenen serbest stil açıklayıcı raporu hazırlarken ve proje sunumunu yaparken doğrudan kullanabileceğin mimari gerekçeleri, kod akışlarını, karşılaşılan zorlukları ve gelecek çalışma önerilerini içerir.

---

## 1. Problemin Tanımı ve Neden Android Seçildi?

- **Problem:** Akıllı telefon kullanım süresinin farkında olmadan günlük hedefleri aşması ve özellikle gece geç saatlerde (örn. `23:00 - 06:00`) uyku düzenini bozacak şekilde ekran başında kalınması.
- **Neden Android?**
  - iOS işletim sistemi, güvenlik ve sandbox politikaları gereği üçüncü parti uygulamaların diğer uygulamaların kullanım sürelerini okumasını büyük ölçüde kısıtlar (`Screen Time / FamilyControls API` özel Apple onayı ve kurumsal/aile profili gerektirir).
  - Android ise kullanıcının açık izniyle (`PACKAGE_USAGE_STATS`) `UsageStatsManager` sistem servisi üzerinden uygulama bazlı ön plan (foreground) sürelerinin okunmasına ve `WindowManager` (`SYSTEM_ALERT_WINDOW`) ile ekran üstü uyarı gösterilmesine olanak tanır.

---

## 2. Mimari Kararlar ve Gerekçeleri

### Karar 1: Offline-First Kural Değerlendirme
- **Nasıl Çalışır?** Günlük limit (`daily_limit_min`) ve kesme saati (`cutoff_start - cutoff_end`) kuralları sunucudan çekildikten sonra telefonda `SharedPreferences` (`LocalStore`) üzerinde önbelleğe alınır.
- **Neden?** Telefonun internet bağlantısı kopsa bile `RuleEvaluator` yerel kuralı kullanarak limit aşımı ve gece modu uyarılarını kesintisiz üretmeye devam eder. Mikroservis telefonu "uzaktan kontrol eden" bir sunucu değil, kuralların merkezi kaynağı ve kullanım istatistiklerinin deposudur.

### Karar 2: İnce (Minimum) Native Katman, Dart'ta İş Mantığı
- **Nasıl Çalışır?** Kotlin kodları ([`UsageReader.kt`](file:///c:/Users/syums/Desktop/project/mobile/android/app/src/main/kotlin/com/screentimeguard/app/UsageReader.kt), [`MonitorService.kt`](file:///c:/Users/syums/Desktop/project/mobile/android/app/src/main/kotlin/com/screentimeguard/app/MonitorService.kt), [`OverlayManager.kt`](file:///c:/Users/syums/Desktop/project/mobile/android/app/src/main/kotlin/com/screentimeguard/app/OverlayManager.kt)) yalnızca Android sistem API'lerine erişir ve ham kullanım verisini `MethodChannel("com.screentimeguard/native")` üzerinden Dart'a aktarır.
- **Neden?** Kural değerlendirme mantığını ([`RuleEvaluator`](file:///c:/Users/syums/Desktop/project/mobile/lib/domain/rule_evaluator.dart)) Kotlin yerine Dart katmanında tutmak, iş mantığının tek bir yerde toplanmasını ve cihaz/emülatör gerektirmeden birim testleriyle ([`rule_evaluator_test.dart`](file:///c:/Users/syums/Desktop/project/mobile/test/rule_evaluator_test.dart)) saniyeler içinde test edilebilmesini sağlar.

---

## 3. Aşama Aşama Teknik Detaylar (Sunumda Anlatım Sırası)

### Aşama 1: Backend Mikroservisi (FastAPI + SQLAlchemy + SQLite)
- **Cihaz Kimlik Doğrulama (`POST /v1/devices`):** Kullanıcı adı/parola karmaşası yerine ilk açılışta cihaz kaydedilir. `secrets.token_urlsafe(32)` ile üretilen `token` istemciye yalnızca bir kez döndürülür; veritabanında (`devices.token_hash`) yalnızca **SHA-256 özeti** saklanır.
- **Standart Hata Zarfı:** Tüm 401, 422 ve 500 hataları özel exception handler'lar ([`main.py`](file:///c:/Users/syums/Desktop/project/backend/app/main.py)) sayesinde tek tip JSON döner:
  ```json
  { "error": { "code": "INVALID_TOKEN", "message": "Geçersiz cihaz token'ı." } }
  ```
- **İdempotent Kullanım Kaydı (`POST /v1/usage`):** `daily_usage` tablosunda `(device_id, date)` üzerinde `UniqueConstraint` vardır. Aynı gün için tekrar veri geldiğinde [`upsert_daily_usage`](file:///c:/Users/syums/Desktop/project/backend/app/services/usage_service.py) mevcut satırın üzerine yazar.

### Aşama 2: Flutter İskeleti ve Gece Yarısını Aşan Kesme Saati
- [`RuleEvaluator.isInCutoffWindow`](file:///c:/Users/syums/Desktop/project/mobile/lib/domain/rule_evaluator.dart):
  - Saatleri gece yarısından itibaren geçen dakikaya (`hour * 60 + minute`) çevirir.
  - Eğer `startMin > endMin` ise (örn. `23:00 - 06:00`), aralığın gece yarısını aştığını tespit eder ve `currentMin >= startMin || currentMin < endMin` formülüyle hem `23:30` hem de `02:15` saatlerini doğru şekilde `in_cutoff_window` olarak işaretler.

### Aşama 3: Native Katman — `UsageStatsManager` ile Süre Okuma
- [`UsageReader.kt`](file:///c:/Users/syums/Desktop/project/mobile/android/app/src/main/kotlin/com/screentimeguard/app/UsageReader.kt):
  - `PACKAGE_USAGE_STATS` izni sıradan bir çalışma zamanı (runtime) izni değildir; `AppOpsManager.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, ...)` ile kontrol edilir ve kullanıcı `Settings.ACTION_USAGE_ACCESS_SETTINGS` ekranına yönlendirilir.
  - Gün başlangıcı (`00:00:00`) ile şu anki zaman aralığı için `queryUsageStats(INTERVAL_DAILY, startOfDayMillis, nowMillis)` çağrılır, paket bazında `totalTimeInForeground` süreleri toplanır, dakikaya çevrilir ve en çok kullanılan ilk 5 uygulama (`top_apps`) sıralanır.

### Aşama 4: İzleme (`MonitorService`) ve Uyarı (`OverlayManager`)
- [`MonitorService.kt`](file:///c:/Users/syums/Desktop/project/mobile/android/app/src/main/kotlin/com/screentimeguard/app/MonitorService.kt):
  - Android pil optimizasyonunun arka plan işlerini sonlandırmasını engellemek için kalıcı bildirimli **Foreground Service** (`START_STICKY`) olarak çalışır.
  - `Handler(Looper.getMainLooper())` ile her **60 saniyede bir** bugünkü kullanımı okur, kalıcı bildirimi günceller ve `MainActivity.sendUsageTickToDart` ile Dart'taki `RuleEvaluator`'ı tetikler.
- [`OverlayManager.kt`](file:///c:/Users/syums/Desktop/project/mobile/android/app/src/main/kotlin/com/screentimeguard/app/OverlayManager.kt):
  - Kuralın `mode` alanı `notify` ise yüksek öncelikli sistem bildirimi gönderir.
  - `mode` alanı `overlay` ise `WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY` kullanarak açık uygulamanın üzerinde uyarı kartı ve `"Anladım / Kapat"` butonu gösterir. Overlay izni verilmemişse uygulama çökmez, güvenli şekilde sistem bildirimine düşer (graceful degradation).
- **Tekrarlayan Uyarı Koruması (Cooldown):** [`AppController._maybeTriggerAlert`](file:///c:/Users/syums/Desktop/project/mobile/lib/presentation/providers.dart) son gösterilen uyarı durumunu ve zaman damgasını saklar; aynı durum için 15 dakika dolmadan kullanıcıyı tekrar tekrar rahatsız etmez.

### Aşama 5: Periyodik Senkronizasyon ve Offline Kuyruk
- [`UsageRepository`](file:///c:/Users/syums/Desktop/project/mobile/lib/data/usage_repository.dart):
  - Her 15 dakikada bir ve kullanıcı manuel yenilediğinde `POST /v1/usage` çağrılır.
  - İnternet yoksa veya sunucuya ulaşılamazsa [`LocalStore.enqueueOfflineUsage`](file:///c:/Users/syums/Desktop/project/mobile/lib/data/local_store.dart) veriyi yerel JSON kuyruğuna yazar (aynı günün kaydı kuyrukta da idempotent olarak güncellenir).
  - Bağlantı tekrar sağlandığında `flushOfflineQueue()` kuyruktaki tüm bekleyen günleri sırayla sunucuya gönderir ve kuyruğu temizler.

---

## 4. Karşılaşılan Zorluklar ve Çözümleri (Raporda "Zorluklar" Başlığı İçin)

1. **Android Özel İzin Akışı (`PACKAGE_USAGE_STATS` ve `SYSTEM_ALERT_WINDOW`):**
   - Standart izin pencereleriyle alınamadığı için uygulama içine özel bir **İzinler Ekranı** ([`permissions_screen.dart`](file:///c:/Users/syums/Desktop/project/mobile/lib/presentation/permissions/permissions_screen.dart)) eklendi; her iznin durumu anlık kontrol edilip kullanıcı doğrudan ilgili Android sistem ayar sayfasına yönlendirildi.
2. **Android Pil Optimizasyonu ve Arka Plan Kısıtlamaları:**
   - Normal arka plan zamanlayıcıları ekran kapandığında işletim sistemi tarafından durdurulduğu için `ForegroundService` (`MonitorService`) ve `specialUse` foreground service tipi kullanıldı.
3. **Yerel Ağda (LAN) Gerçek Cihaz Testi:**
   - Emülatörde kullanılan `10.0.2.2` adresi gerçek telefonda çalışmaz. Bu yüzden ana ekrana **"Sunucu Adresini Düzenle"** penceresi eklendi ve `AndroidManifest.xml` içinde `android:usesCleartextTraffic="true"` tanımlanarak yerel Wi-Fi IP'si üzerinden HTTP testi kolaylaştırıldı (üretim ortamında HTTPS zorunlu olmalıdır).

---

## 5. Sınırlılıklar ve Gelecek Çalışma Önerileri

- **iOS Desteği:** Apple `Screen Time API` (`DeviceActivity` & `FamilyControls`) entegrasyonu ile iOS platformuna genişletilmesi.
- **Uygulama Bazlı Engelleme:** Yalnızca toplam ekran süresi yerine `AccessibilityService` kullanılarak belirli uygulamalara (örn. sadece sosyal medya için günde 30 dk) özel limit konulması.
- **Ebeveyn / Aile Paneli:** Birden fazla cihazın tek bir web veya mobil ebeveyn hesabından yönetilebilmesi ve JWT tabanlı çoklu kullanıcı kimlik doğrulaması.
