from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.deps import hash_token
from app.models import Device


def test_health_check(client: TestClient) -> None:
    """GET /v1/health token gerektirmeden 200 OK döndürmelidir."""
    response = client.get("/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_register_device_and_token_hashing(client: TestClient, db_session: Session) -> None:
    """
    POST /v1/devices yeni cihaz oluşturmalı, açık token döndürmeli,
    ancak veritabanında yalnızca token'ın SHA-256 hash'ini saklamalıdır.
    """
    response = client.post("/v1/devices", json={"name": "Samsung Galaxy S23"})
    assert response.status_code == 201

    data = response.json()
    assert "device_id" in data
    assert "token" in data
    assert data["name"] == "Samsung Galaxy S23"

    raw_token = data["token"]
    device_in_db = db_session.execute(
        select(Device).where(Device.id == data["device_id"])
    ).scalar_one()

    # Güvenlik kontrolü: DB'deki değer ham token olmamalı, SHA-256 özeti olmalı
    assert device_in_db.token_hash != raw_token
    assert device_in_db.token_hash == hash_token(raw_token)


def test_unauthorized_access_returns_standard_error(client: TestClient) -> None:
    """Token olmadan veya geçersiz token ile yapılan istekler standart hata formatında 401 dönmelidir."""
    # 1. Başlık hiç gönderilmediğinde
    res_missing = client.get("/v1/rules")
    assert res_missing.status_code == 401
    body_missing = res_missing.json()
    assert "error" in body_missing
    assert body_missing["error"]["code"] == "INVALID_TOKEN"

    # 2. Geçersiz bir token gönderildiğinde
    res_invalid = client.get("/v1/rules", headers={"X-Device-Token": "sahte-gecersiz-token"})
    assert res_invalid.status_code == 401
    body_invalid = res_invalid.json()
    assert body_invalid["error"]["code"] == "INVALID_TOKEN"


def test_get_and_update_rules(client: TestClient) -> None:
    """Cihaz kaydından sonra varsayılan kural okunabilmeli ve PUT /v1/rules ile güncellenebilmelidir."""
    reg = client.post("/v1/devices", json={"name": "Pixel 7"}).json()
    headers = {"X-Device-Token": reg["token"]}

    # Varsayılan kuralı oku
    get_res = client.get("/v1/rules", headers=headers)
    assert get_res.status_code == 200
    default_rule = get_res.json()
    assert default_rule["daily_limit_min"] == 120
    assert default_rule["cutoff_start"] == "23:00"
    assert default_rule["cutoff_end"] == "06:00"
    assert default_rule["mode"] == "notify"

    # Kuralı güncelle (gece yarısını aşan kesme saati ve overlay modu)
    update_payload = {
        "daily_limit_min": 90,
        "cutoff_start": "22:30",
        "cutoff_end": "06:30",
        "mode": "overlay",
    }
    put_res = client.put("/v1/rules", json=update_payload, headers=headers)
    assert put_res.status_code == 200
    updated = put_res.json()
    assert updated["daily_limit_min"] == 90
    assert updated["cutoff_start"] == "22:30"
    assert updated["cutoff_end"] == "06:30"
    assert updated["mode"] == "overlay"


def test_rule_validation_error_format(client: TestClient) -> None:
    """Geçersiz saat formatı gönderildiğinde 422 ve standart hata zarfı dönmelidir."""
    reg = client.post("/v1/devices").json()
    headers = {"X-Device-Token": reg["token"]}

    bad_payload = {
        "daily_limit_min": 120,
        "cutoff_start": "25:99",  # Geçersiz saat
        "cutoff_end": "06:00",
        "mode": "overlay",
    }
    res = client.put("/v1/rules", json=bad_payload, headers=headers)
    assert res.status_code == 422
    err = res.json()
    assert err["error"]["code"] == "VALIDATION_ERROR"


def test_post_usage_is_idempotent(client: TestClient) -> None:
    """
    Aynı gün (date) için birden fazla POST /v1/usage gönderildiğinde
    yeni satır açmak yerine mevcut kaydın üzerine yazmalıdır (idempotency).
    """
    reg = client.post("/v1/devices", json={"name": "Test Phone"}).json()
    headers = {"X-Device-Token": reg["token"]}

    # İlk gönderim: 22 Ekim 2026, 85 dakika
    first_payload = {
        "date": "2026-10-22",
        "total_minutes": 85,
        "top_apps": [{"package": "com.instagram.android", "minutes": 40}],
    }
    res1 = client.post("/v1/usage", json=first_payload, headers=headers)
    assert res1.status_code == 200
    assert res1.json()["total_minutes"] == 85

    # Aynı gün için ikinci gönderim: 143 dakika
    second_payload = {
        "date": "2026-10-22",
        "total_minutes": 143,
        "top_apps": [
            {"package": "com.instagram.android", "minutes": 75},
            {"package": "com.google.android.youtube", "minutes": 48},
        ],
    }
    res2 = client.post("/v1/usage", json=second_payload, headers=headers)
    assert res2.status_code == 200
    assert res2.json()["total_minutes"] == 143
    assert len(res2.json()["top_apps"]) == 2

    # Geçmiş sorgulandığında aynı gün için tek kayıt olmalı
    history_res = client.get("/v1/usage?days=7", headers=headers)
    assert history_res.status_code == 200
    history = history_res.json()
    assert len(history["items"]) == 1
    assert history["items"][0]["total_minutes"] == 143
    assert history["average_minutes"] == 143.0


def test_usage_history_and_average_calculation(client: TestClient) -> None:
    """Birden fazla günün kullanım verisi gönderildiğinde ortalama doğru hesaplanmalıdır."""
    reg = client.post("/v1/devices").json()
    headers = {"X-Device-Token": reg["token"]}

    samples = [
        {"date": "2026-10-20", "total_minutes": 100, "top_apps": []},
        {"date": "2026-10-21", "total_minutes": 150, "top_apps": []},
        {"date": "2026-10-22", "total_minutes": 200, "top_apps": []},
    ]
    for sample in samples:
        res = client.post("/v1/usage", json=sample, headers=headers)
        assert res.status_code == 200

    history_res = client.get("/v1/usage?days=7", headers=headers)
    assert history_res.status_code == 200
    data = history_res.json()

    assert data["days"] == 7
    assert len(data["items"]) == 3
    # (100 + 150 + 200) / 3 = 150.0
    assert data["average_minutes"] == 150.0
    # Kayıtlar en yeni tarihten eskiye sıralı gelmeli
    assert data["items"][0]["date"] == "2026-10-22"
    assert data["items"][-1]["date"] == "2026-10-20"
