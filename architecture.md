# screentime-guard: Mimari Dokümanı

Mobil Teknolojiler dersi projesi. Android telefonda günlük ekran kullanım süresini takip eden, günlük limit aşıldığında veya belirli bir saat aralığında kullanıcıyı uyaran bir sistem ve bu sistemin kurallarını/istatistiklerini yöneten küçük bir mikroservis.

## 1. Amaç ve kapsam

- Telefonun günlük toplam kullanım süresini ölçmek.
- Günlük limit aşılınca veya kesme saati aralığında (örn. 23:00-06:00) bildirim ya da ekran üstü uyarı (overlay) göstermek.
- Kuralları ve kullanım geçmişini bir mikroservis üzerinde saklamak, haftalık istatistik sunmak.

Kapsam dışı: iOS desteği, çoklu kullanıcı hesabı/parola sistemi, uygulama bazlı engelleme (Accessibility Service). Bunlar isteğe bağlı geliştirme olarak raporda "gelecek çalışma" başlığında anılabilir.

## 2. Teknoloji seçimleri

| Katman | Seçim | Gerekçe |
|---|---|---|
| Mobil | Flutter (Android hedefli) | Tek kod tabanı, hızlı arayüz geliştirme |
| Native katman | Kotlin | Sistem API'lerine (UsageStatsManager, Service, Overlay) erişim için gerekli |
| State management | Riverpod | Basit, test edilebilir |
| HTTP istemcisi | dio | Interceptor ile token ekleme kolaylığı |
| Backend | Python + FastAPI | Hızlı geliştirme, otomatik `/docs` sayfası |
| Veritabanı | SQLite + SQLAlchemy | Kurulum gerektirmez, proje ölçeğine yeterli |
| Doğrulama | Pydantic | Şema doğrulama |
| Test | pytest | Backend testleri |

Neden Android? iOS, uygulamaların diğer uygulamaların kullanım süresini okumasını ve engellemesini büyük ölçüde kısıtlar (Screen Time API'si ayrı izin ve Apple onayı ister). Android'de `UsageStatsManager` ile bu mümkündür.

## 3. Genel mimari

```
┌────────────────────────── Android telefon ──────────────────────────┐
│ Flutter UI (Dart)                                                   │
│   ├─ presentation: Dashboard, Kurallar, Geçmiş, İzinler             │
│   ├─ domain: UsageRecord, Rule, RuleEvaluator                       │
│   └─ data: ApiClient, LocalStore, UsageRepository, RuleRepository   │
│            │ MethodChannel                                          │
│ Kotlin (native katman)                                              │
│   ├─ UsageReader      → UsageStatsManager ile bugünkü süre          │
│   ├─ MonitorService   → foreground service, periyodik kontrol       │
│   └─ OverlayManager   → ekran üstü uyarı penceresi                  │
└───────────────┬─────────────────────────────────────────────────────┘
                │ HTTPS/JSON + X-Device-Token
┌───────────────▼──────────── Mikroservis ───────────────────────────┐
│ FastAPI: routers → services → SQLAlchemy models → SQLite            │
└─────────────────────────────────────────────────────────────────────┘
```

### Temel tasarım kararları

1. **Offline-first kural değerlendirme.** Limit ve saat kontrolü telefonda yapılır. İnternet olmasa da uyarılar çalışır. Servis, kuralların kaynağı ve istatistiklerin deposudur; telefonu "uzaktan kontrol etmez".
2. **Native katman minimumda.** Kotlin yalnızca sistem API'lerine erişir ve ham veriyi Dart'a iletir. İş mantığı (kural değerlendirme) Dart'ta kalır; böylece test edilebilir ve tek yerde toplanır.
3. **Basit cihaz kimliği.** İlk açılışta cihaz kaydedilir, servis rastgele bir `device_token` üretir. Sonraki isteklerde `X-Device-Token` header'ı kullanılır. Serviste token'ın yalnızca hash'i saklanır.
4. **Idempotent senkronizasyon.** Aynı gün için gelen kullanım verisi üzerine yazılır; tekrar gönderim güvenlidir.

## 4. Klasör yapısı

```
screentime-guard/
├─ backend/
│  ├─ app/
│  │  ├─ main.py
│  │  ├─ config.py
│  │  ├─ db.py              # engine ve session
│  │  ├─ models.py          # Device, Rule, DailyUsage
│  │  ├─ schemas.py         # Pydantic şemaları
│  │  ├─ deps.py            # token doğrulama bağımlılığı
│  │  ├─ routers/           # devices.py, rules.py, usage.py
│  │  └─ services/          # usage_service.py
│  ├─ tests/
│  ├─ requirements.txt
│  └─ Dockerfile
├─ mobile/
│  ├─ lib/
│  │  ├─ main.dart
│  │  ├─ core/              # api_client.dart, constants.dart
│  │  ├─ data/              # usage_repository.dart, rule_repository.dart, local_store.dart
│  │  ├─ domain/            # rule.dart, usage_record.dart, rule_evaluator.dart
│  │  ├─ platform/          # usage_channel.dart (MethodChannel sarmalayıcı)
│  │  └─ presentation/      # dashboard/, rules/, history/, permissions/
│  └─ android/app/src/main/kotlin/.../
│     ├─ MainActivity.kt    # channel handler
│     ├─ UsageReader.kt
│     ├─ MonitorService.kt
│     └─ OverlayManager.kt
├─ docs/
│  ├─ architecture.md
│  └─ report-notes.md
└─ README.md
```

## 5. Veri modeli

### devices
| Alan | Tip | Not |
|---|---|---|
| id | uuid (PK) | |
| token_hash | string | Token'ın hash'i |
| name | string | Cihaz adı |
| created_at | datetime | |

### rules
| Alan | Tip | Not |
|---|---|---|
| device_id | uuid (FK) | Cihaz başına tek kural |
| daily_limit_min | int | Günlük limit (dakika) |
| cutoff_start | string (HH:MM) | Örn. 23:00 |
| cutoff_end | string (HH:MM) | Örn. 06:00 |
| mode | enum | `notify` veya `overlay` |
| updated_at | datetime | |

### daily_usage
| Alan | Tip | Not |
|---|---|---|
| device_id | uuid (FK) | |
| date | date | (device_id, date) benzersiz |
| total_minutes | int | |
| top_apps | JSON | En çok kullanılan uygulamalar |
| synced_at | datetime | |

## 6. API sözleşmesi

Tüm istekler (`POST /v1/devices` ve `GET /v1/health` hariç) `X-Device-Token` header'ı ister.

| Metot | Yol | Açıklama |
|---|---|---|
| POST | `/v1/devices` | Cihaz kaydı. Yanıt: `{device_id, token}` |
| GET | `/v1/rules` | Cihazın mevcut kuralı |
| PUT | `/v1/rules` | Kuralı oluştur/güncelle |
| POST | `/v1/usage` | Günlük kullanımı gönder (idempotent) |
| GET | `/v1/usage?days=7` | Geçmiş kayıtlar ve ortalama |
| GET | `/v1/health` | Servis sağlık kontrolü |

Örnek istek/yanıt:

```json
// PUT /v1/rules
{ "daily_limit_min": 120, "cutoff_start": "23:00", "cutoff_end": "06:00", "mode": "overlay" }

// POST /v1/usage
{ "date": "2026-10-22", "total_minutes": 143, "top_apps": [{"package": "com.example.app", "minutes": 52}] }
```

Hata formatı (tüm hatalarda aynı):

```json
{ "error": { "code": "INVALID_TOKEN", "message": "Geçersiz cihaz token'ı." } }
```

## 7. Telefon tarafı akışı

1. **İlk açılış:** İzin ekranı (Usage Access, Overlay, bildirim) → cihaz kaydı → kurallar çekilip yerelde saklanır.
2. **İzleme:** `MonitorService` (foreground service) 60 saniyede bir bugünkü toplam süreyi okur ve Dart'a iletir.
3. **Karar:** `RuleEvaluator` şu durumlardan birini üretir: `ok`, `warn_80` (limitin %80'i), `limit_exceeded`, `in_cutoff_window`.
4. **Aksiyon:** Karara göre bildirim veya overlay gösterilir. Aynı uyarının tekrar tekrar çıkmaması için son uyarı zamanı saklanır.
5. **Senkronizasyon:** Her 15 dakikada ve gün sonunda `POST /v1/usage`. Başarısız olursa yerel kuyruğa yazılır, bağlantı gelince yeniden denenir.

### Dikkat edilecek noktalar

- Kesme saati gece yarısını aşabilir (23:00-06:00). `RuleEvaluator` bu durumu doğru ele almalı ve test edilmeli.
- Android pil optimizasyonu arka plan işlerini sonlandırabilir; foreground service ve kalıcı bildirim bunun için kullanılır.
- Android 13 ve üzerinde bildirim izni (`POST_NOTIFICATIONS`) ayrıca istenir.
- Kullanım verisi emülatörde neredeyse boştur; test ve demo gerçek cihazda yapılmalı.
- Gerekli izinler: `PACKAGE_USAGE_STATS` (ayarlardan elle), `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE`, `POST_NOTIFICATIONS`, `INTERNET`.

## 8. Güvenlik ve gizlilik

- Token servis tarafında hash'lenerek saklanır.
- Yalnızca toplam süre ve en çok kullanılan uygulamalar gönderilir; ekran içeriği veya uygulama içi veri toplanmaz.
- Kullanıcı izinleri açıkça ve ayrı ayrı ister, izin verilmezse uygulama ilgili özelliği devre dışı bırakır.
- Üretim ortamında HTTPS zorunlu olmalıdır (ders projesinde yerel ağda HTTP ile test edilebilir, raporda belirtilmeli).

## 9. Test stratejisi

- **Backend:** pytest ile endpoint testleri (cihaz kaydı, yetkisiz erişim, kural güncelleme, aynı gün için tekrar usage gönderimi).
- **Mobil:** `RuleEvaluator` için birim testleri (limit aşımı, gece yarısını aşan kesme saati, %80 uyarısı).
- **Manuel:** Gerçek cihazda izin akışı, uyarı gösterimi ve internet yokken davranış.

## 10. Geliştirme aşamaları

1. **Backend:** modeller, endpoint'ler, testler; `/docs` üzerinden doğrulama.
2. **Flutter iskeleti:** klasör yapısı, API client, kurallar ve geçmiş ekranları.
3. **Native katman:** `UsageStatsManager` ile süre okuma, Dart'ta gösterme.
4. **İzleme ve uyarı:** foreground service, `RuleEvaluator`, bildirim/overlay.
5. **Senkronizasyon:** offline kuyruk ve yeniden deneme.
6. **Rapor:** mimari, karar gerekçeleri, ekran görüntüleri, karşılaşılan sorunlar.

## 11. Rapor için notlar

Raporda şu başlıklar işe yarar: problemin tanımı, neden Android seçildi, mimari diyagram ve kararların gerekçesi (özellikle offline-first ve ince native katman), karşılaşılan zorluklar (izinler, arka plan kısıtlamaları), AI araçlarının nasıl kullanıldığı, sınırlılıklar ve gelecek çalışma (iOS, uygulama bazlı limit, aile/ebeveyn paneli).
