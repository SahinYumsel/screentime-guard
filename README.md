# screentime-guard

Mobil Teknolojiler dersi projesi. Android telefonda günlük ekran kullanım süresini takip eden, günlük limit aşıldığında veya belirli bir saat aralığında (örn. 23:00–06:00) kullanıcıyı bildirim ya da ekran üstü uyarı (overlay) ile uyaran offline-first mobil uygulama ve mikroservis sistemi.

## Klasör Yapısı

```text
screentime-guard/
├─ backend/
│  ├─ app/
│  │  ├─ main.py              # FastAPI uygulaması, exception handler'lar, /v1/health
│  │  ├─ config.py            # Uygulama ayarları ve varsayılan kural sabitleri
│  │  ├─ db.py                # SQLAlchemy engine ve get_db oturum yöneticisi
│  │  ├─ models.py            # Device, Rule, DailyUsage ORM modelleri
│  │  ├─ schemas.py           # Pydantic istek/yanıt ve doğrulama şemaları
│  │  ├─ deps.py              # X-Device-Token SHA-256 doğrulama bağımlılığı
│  │  ├─ routers/             # devices.py, rules.py, usage.py
│  │  └─ services/            # usage_service.py (idempotent upsert ve ortalama hesabı)
│  ├─ tests/                  # pytest uç nokta testleri
│  ├─ requirements.txt
│  └─ Dockerfile
├─ mobile/
│  ├─ lib/
│  │  ├─ main.dart
│  │  ├─ core/                # constants.dart, api_client.dart (Dio + X-Device-Token interceptor)
│  │  ├─ domain/              # rule.dart, usage_record.dart, rule_evaluator.dart
│  │  ├─ data/                # local_store.dart, rule_repository.dart, usage_repository.dart
│  │  ├─ platform/            # usage_channel.dart (MethodChannel sarmalayıcısı)
│  │  └─ presentation/        # dashboard/, rules/, history/, permissions/, providers.dart
│  ├─ android/app/src/main/
│  │  ├─ AndroidManifest.xml
│  │  └─ kotlin/com/screentimeguard/app/
│  │     ├─ MainActivity.kt   # MethodChannel ("com.screentimeguard/native") köprüsü
│  │     ├─ UsageReader.kt    # UsageStatsManager ile bugünkü süre ve top_apps okuma
│  │     ├─ MonitorService.kt # 60 sn'de bir kontrol yapan Foreground Service
│  │     └─ OverlayManager.kt # Bildirim ve WindowManager ekran üstü uyarı penceresi
│  └─ test/                   # RuleEvaluator ve offline senkronizasyon kuyruğu birim testleri
├─ docs/
│  ├─ architecture.md         # Mimari tasarım dokümanı
│  └─ report-notes.md         # Rapor ve sunum için detaylı teknik açıklama notları
└─ README.md
```

---

## 1. Backend Kurulum ve Çalıştırma

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Geliştirme sunucusunu yerel ağdaki cihazların erişimine açık olarak başlatma:
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- **Swagger UI (Etkileşimli API Dokümanı):** `http://localhost:8000/docs`
- **Sağlık Kontrolü:** `http://localhost:8000/v1/health`

### Backend Testlerini Çalıştırma

```powershell
cd backend
.\.venv\Scripts\pytest.exe -v
```

---

## 2. Mobil Uygulama (Flutter + Android) Çalıştırma ve Gerçek Cihaz Testi

```powershell
cd mobile
flutter pub get

# Birim testlerini çalıştırma (RuleEvaluator + Offline Queue):
flutter test

# USB ile bağlı gerçek Android cihazda çalıştırma:
flutter run
```

### Gerçek Cihazda Mikroservise Bağlanma İpucu
1. Bilgisayar ve Android telefon aynı Wi-Fi ağına bağlı olmalıdır.
2. Bilgisayarın yerel IP adresini öğrenin (`ipconfig` -> IPv4 Address, örn. `192.168.1.45`).
3. Backend'i `--host 0.0.0.0 --port 8000` ile başlatın.
4. Uygulamanın ana ekranındaki (**Durum** sekmesi) sağ üst **Sunucu Adresini Düzenle** ikonuna dokunup `http://192.168.1.45:8000` adresini kaydedin.
