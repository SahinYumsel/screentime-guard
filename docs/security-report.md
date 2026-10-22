# Siber Güvenlik Değerlendirme ve Test Raporu (`screentime-guard`)

**Tarih:** 22 Ekim 2026  
**Kapsam:** `screentime-guard` FastAPI Mikroservisi (`backend/`) ve Flutter + Kotlin Mobil İstemcisi (`mobile/`)  
**Referans Standartlar:** OWASP API Security Top 10 (2023), OWASP Mobile Application Security (MASVS / Mobile Top 10)

---

## 1. Yönetici Özeti

Bu rapor, **Mobil Teknolojiler** dersi kapsamında geliştirilen `screentime-guard` sisteminin hem **mikroservis (API ve veritabanı)** hem de **Android mobil uygulama (Flutter + Kotlin native katmanı)** bileşenlerinin siber güvenlik açısından incelenmesi, otomatik güvenlik doğrulama testlerinin (`pytest`) koşulması ve üretim ortamı (production) için sertleştirme (hardening) önerilerinin belgelenmesi amacıyla hazırlanmıştır.

Sistemde **Saldırı Yüzeyi Minimilizasyonu (Attack Surface Minimization)** ve **Tasarımdan İtibaren Gizlilik (Privacy by Design)** ilkeleri benimsenmiştir:
- Cihaz kimlik doğrulama anahtarları (`device_token`) veritabanında açık metin (plaintext) olarak **tutulmaz**, yalnızca **SHA-256 özeti (`token_hash`)** saklanır.
- Kullanıcıdan kişisel kimlik verisi (ad, e-posta, telefon numarası) veya uygulama içi ekran görüntüsü/klavye girdisi **toplanmaz**; yalnızca günlük toplam dakika ve paket adları (`top_apps`) işlenir.

---

## 2. Otomatik Güvenlik Doğrulama Testleri (`backend/tests/test_security.py`)

Mikroservis üzerinde 5 ana güvenlik kontrolünü doğrulayan otomatik test senaryoları yazılmış ve `pytest` ile doğrulanmıştır (**Toplam 12/12 test başarılı**):

| Test Adı | OWASP Kategorisi | Kontrol Edilen Güvenlik Mekanizması | Sonuç |
|---|---|---|---|
| `test_token_entropy_and_sha256_storage` | API2:2023 Broken Authentication | `secrets.token_urlsafe(32)` ile yüksek entropili (256-bit) token üretimi ve DB'de yalnızca 64 karakterlik SHA-256 hash saklanması. | **GEÇTİ (PASSED)** |
| `test_device_data_isolation` | API1:2023 Broken Object Level Authorization (BOLA / IDOR) | İki farklı cihazın (`Device A` ve `Device B`) birbirinin kurallarını (`GET/PUT /v1/rules`) veya kullanım geçmişini (`GET /v1/usage`) okuyamaması ve değiştirememesi. | **GEÇTİ (PASSED)** |
| `test_input_boundary_and_payload_limits` | API4:2023 Unrestricted Resource Consumption | Günlük maksimum dakika sınırı (`0..1440`), cihaz adı uzunluk sınırı (`<=100` karakter) ve `top_apps` dizi boyutu sınırının (`<=20` uygulama) aşılması durumunda `422 VALIDATION_ERROR` ile reddedilmesi. | **GEÇTİ (PASSED)** |
| `test_special_characters_handled_safely_by_orm` | API8:2023 Security Misconfiguration / Injection | `X-Device-Token` ve JSON alanlarında özel SQL karakterlerinin SQLAlchemy parametreli sorguları (Prepared Statements) tarafından güvenle işlenmesi. | **GEÇTİ (PASSED)** |
| `test_error_responses_do_not_leak_internals` | API8:2023 Security Misconfiguration | 401, 404 ve 422 hata yanıtlarında Python stack trace, dosya yolu veya SQLAlchemy iç bilgisinin dışarı sızdırılmaması (`{"error": {"code": ..., "message": ...}}`). | **GEÇTİ (PASSED)** |

---

## 3. Uygulanan Güvenlik Önlemleri (Mevcut Kontroller)

### 3.1. Kriptografik Token Üretimi ve Hashleme ([deps.py](file:///c:/Users/syums/Desktop/project/backend/app/deps.py))
- Standart `random` modülü yerine işletim sisteminin kriptografik rastgele sayı üretecini (CSPRNG) kullanan `secrets.token_urlsafe(32)` tercih edilmiştir.
- Veritabanı (`screentime_guard.db`) sızdırılsa bile saldırganlar `token_hash` değerinden ham `X-Device-Token` değerini elde edemez (SHA-256 tek yönlü özet fonksiyonu).

### 3.2. SQL Enjeksiyon (SQLi) Koruması ([models.py](file:///c:/Users/syums/Desktop/project/backend/app/models.py), [usage_service.py](file:///c:/Users/syums/Desktop/project/backend/app/services/usage_service.py))
- Tüm veritabanı işlemleri ham SQL metin birleştirmesi yerine SQLAlchemy 2.0 ORM (`select(Device).where(...)`) ile parametreli olarak yürütülür.

### 3.3. Katı Şema ve Sınır Doğrulaması ([schemas.py](file:///c:/Users/syums/Desktop/project/backend/app/schemas.py))
- `daily_limit_min` ve `total_minutes` alanları bir gündeki toplam dakika sayısı olan `1440` ile sınırlandırılmıştır.
- `cutoff_start` ve `cutoff_end` alanları yalnızca geçerli 24 saat formatını (`^([01]\d|2[0-3]):[0-5]\d$`) kabul eder.
- Bellek şişirme (Payload DoS) riskine karşı `top_apps` listesine `max_length=20` sınırı uygulanmıştır.

### 3.4. Android Bileşen İzolasyonu ve Yedekleme Koruması ([AndroidManifest.xml](file:///c:/Users/syums/Desktop/project/mobile/android/app/src/main/AndroidManifest.xml))
- Arka planda çalışan `MonitorService` bileşeninde `android:exported="false"` tanımlanmıştır; böylece telefondaki diğer üçüncü parti uygulamalar bu servisi dışarıdan tetikleyemez veya durduramaz.
- `<application>` etiketine `android:allowBackup="false"` eklenerek `adb backup` üzerinden yerel `SharedPreferences` verilerinin (ve cihaz token'ının) dışarı kopyalanması engellenmiştir.

---

## 4. Tespit Edilen Riskler ve Üretim Ortamı (Production) İçin İyileştirme Önerileri

Ders projesi ve yerel ağ (LAN) test ortamı için bilinçli olarak basitleştirilen, ancak gerçek bir üretim (production) ortamına çıkarken kapatılması gereken bulgular aşağıda derecelendirilmiştir:

### Bulgu 1: İletişim Kanalı Şifrelemesi (`usesCleartextTraffic="true"`) — **Risk Seviyesi: Orta (OWASP Mobile M5)**
- **Açıklama:** Yerel geliştirme ortamında (`http://127.0.0.1:8000` veya `http://192.168.x.x:8000`) kendinden imzalı sertifika hatası almamak için `AndroidManifest.xml` içinde HTTP (şifresiz metin) trafiğine izin verilmiştir.
- **Etki:** Güvensiz ortak Wi-Fi ağlarında Ortadaki Adam (MITM) saldırısı ile `X-Device-Token` başlığı dinlenebilir.
- **Çözüm Önerisi:** Üretim ortamında mikroservis bir TLS/HTTPS ters vekil sunucusu (Nginx / Cloudflare) arkasına alınmalı, `AndroidManifest.xml` içinde `android:usesCleartextTraffic="false"` yapılmalı ve gerekirse **Certificate Pinning** uygulanmalıdır.

### Bulgu 2: Cihaz Kayıt Uç Noktasında Hız Sınırlandırma (Rate Limiting) Eksikliği — **Risk Seviyesi: Orta (OWASP API4)**
- **Açıklama:** `POST /v1/devices` uç noktası ilk açılışta çağrıldığı için kimlik doğrulama gerektirmez. Şu an IP bazlı bir istek sınırlandırması (Rate Limiting) bulunmamaktadır.
- **Etki:** Kötü niyetli bir istemci saniyede binlerce `POST /v1/devices` isteği göndererek SQLite veritabanında sahte cihaz kayıtları oluşturabilir.
- **Çözüm Önerisi:** Üretim ortamında `slowapi` (FastAPI rate limiter) veya API Gateway katmanında IP başına dakikada en fazla 5 cihaz kaydı (`5 req/min`) sınırı konulmalı ve Google Play Integrity API ile isteğin gerçek bir Android cihazdan geldiği doğrulanmalıdır.

### Bulgu 3: Mobil Cihazda Token Saklama Yöntemi (`SharedPreferences`) — **Risk Seviyesi: Düşük/Orta (OWASP Mobile M9)**
- **Açıklama:** `device_token` değeri şu anda uygulama kum havuzu (sandbox) içindeki `SharedPreferences` XML dosyasında saklanmaktadır (`android:allowBackup="false"` ile yedeklemeye karşı korunmuştur).
- **Etki:** Normal cihazlarda diğer uygulamalar bu dosyaya erişemez; ancak **root** yetkisi alınmış (rooted) bir cihazda dosya sistemi okunabilir.
- **Çözüm Önerisi:** Hassas token verisinin Android donanım destekli anahtar deposunda (**Android Keystore**) AES ile şifrelenerek tutulması için `flutter_secure_storage` paketine geçilmesi önerilir.

### Bulgu 4: CORS Politikası (`allow_origins=["*"]`) — **Risk Seviyesi: Düşük (OWASP API8)**
- **Açıklama:** [main.py](file:///c:/Users/syums/Desktop/project/backend/app/main.py) içinde geliştirme kolaylığı için tüm origin'lere izin verilmiştir.
- **Çözüm Önerisi:** İstemci yalnızca native Android uygulaması olduğu için üretim ortamında tarayıcı tabanlı çapraz köken (CORS) erişimi tamamen kapatılmalı veya yalnızca yetkili yönetim paneli alan adıyla sınırlandırılmalıdır.

---

## 5. Sonuç

`screentime-guard` projesi; **SHA-256 token hashleme**, **cihazlar arası tam veri izolasyonu (BOLA/IDOR koruması)**, **SQLAlchemy parametreli sorguları**, **Pydantic sınır doğrulamaları (`max_length`, `0..1440` dk)**, **Android servis izolasyonu (`exported="false"`)** ve **veri minimizasyonu** sayesinde ders projesi ölçeğinde güçlü ve doğrulanmış bir güvenlik temeline sahiptir.
