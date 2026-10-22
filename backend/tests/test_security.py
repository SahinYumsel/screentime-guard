from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.deps import hash_token
from app.models import Device


def test_token_entropy_and_sha256_storage(client: TestClient, db_session: Session) -> None:
    """
    Üretilen cihaz token'ı yüksek entropiye sahip olmalı, iki farklı cihaz için
    benzersiz üretilmeli ve veritabanında yalnızca 64 karakterlik SHA-256 özeti tutulmalıdır.
    """
    reg1 = client.post("/v1/devices", json={"name": "Device 1"}).json()
    reg2 = client.post("/v1/devices", json={"name": "Device 2"}).json()

    token1 = reg1["token"]
    token2 = reg2["token"]

    assert token1 != token2
    assert len(token1) >= 32

    dev1 = db_session.execute(select(Device).where(Device.id == reg1["device_id"])).scalar_one()
    assert dev1.token_hash != token1
    assert len(dev1.token_hash) == 64
    assert dev1.token_hash == hash_token(token1)


def test_device_data_isolation(client: TestClient) -> None:
    """
    Cihazlar arası veri izolasyonu (OWASP API1 - BOLA/IDOR kontrolü):
    A cihazı kendi kuralını ve kullanımını güncellediğinde, B cihazının kuralı
    veya kullanım geçmişi bundan etkilenmemeli ve birbirlerinin verisini görememelidir.
    """
    dev_a = client.post("/v1/devices", json={"name": "Device A"}).json()
    dev_b = client.post("/v1/devices", json={"name": "Device B"}).json()

    headers_a = {"X-Device-Token": dev_a["token"]}
    headers_b = {"X-Device-Token": dev_b["token"]}

    # A cihazı kuralını ve kullanımını günceller
    client.put(
        "/v1/rules",
        json={
            "daily_limit_min": 45,
            "cutoff_start": "21:00",
            "cutoff_end": "07:00",
            "mode": "overlay",
        },
        headers=headers_a,
    )
    client.post(
        "/v1/usage",
        json={
            "date": "2026-10-22",
            "total_minutes": 300,
            "top_apps": [{"package": "com.example.a", "minutes": 120}],
        },
        headers=headers_a,
    )

    # B cihazı kendi kuralını ve geçmişini sorguladığında A'nın verilerini görmemelidir
    rule_b = client.get("/v1/rules", headers=headers_b).json()
    assert rule_b["device_id"] == dev_b["device_id"]
    assert rule_b["daily_limit_min"] == 120  # Varsayılan değer korunmalı

    usage_b = client.get("/v1/usage?days=7", headers=headers_b).json()
    assert usage_b["items"] == []
    assert usage_b["average_minutes"] == 0.0


def test_input_boundary_and_payload_limits(client: TestClient) -> None:
    """
    Sınır değer ve kaynak tüketimi kontrolleri (OWASP API4):
    - Bir gündeki maksimum dakika (1440) üzerindeki değerler reddedilmeli
    - Negatif süreler reddedilmeli
    - top_apps listesinde 20'den fazla eleman gönderilmesi reddedilmeli
    - 100 karakterden uzun cihaz adı reddedilmeli
    """
    # 1. Çok uzun cihaz adı (>100 karakter)
    long_name_res = client.post("/v1/devices", json={"name": "X" * 150})
    assert long_name_res.status_code == 422
    assert long_name_res.json()["error"]["code"] == "VALIDATION_ERROR"

    reg = client.post("/v1/devices", json={"name": "Security Test Phone"}).json()
    headers = {"X-Device-Token": reg["token"]}

    # 2. Bir günde 1440 dakikadan fazla süre (> 24 saat)
    over_day_res = client.post(
        "/v1/usage",
        json={"date": "2026-10-22", "total_minutes": 1500, "top_apps": []},
        headers=headers,
    )
    assert over_day_res.status_code == 422

    # 3. Negatif ekran süresi
    negative_res = client.post(
        "/v1/usage",
        json={"date": "2026-10-22", "total_minutes": -10, "top_apps": []},
        headers=headers,
    )
    assert negative_res.status_code == 422

    # 4. Aşırı büyük top_apps listesi (> 20 uygulama)
    oversized_apps = [{"package": f"com.app.num{i}", "minutes": 1} for i in range(25)]
    oversized_res = client.post(
        "/v1/usage",
        json={"date": "2026-10-22", "total_minutes": 25, "top_apps": oversized_apps},
        headers=headers,
    )
    assert oversized_res.status_code == 422
    assert oversized_res.json()["error"]["code"] == "VALIDATION_ERROR"


def test_special_characters_handled_safely_by_orm(client: TestClient) -> None:
    """
    SQLAlchemy parametreli sorgularının özel karakter içeren token veya
    cihaz adlarını güvenli şekilde işlediğini doğrular.
    """
    special_token = "token-with-special-chars-'\"--;/*"
    res = client.get("/v1/rules", headers={"X-Device-Token": special_token})
    assert res.status_code == 401
    assert res.json()["error"]["code"] == "INVALID_TOKEN"


def test_error_responses_do_not_leak_internals(client: TestClient) -> None:
    """
    Hata yanıtlarında sunucu dosya yolları, SQL sorguları veya stack trace
    sızdırılmamalı; yalnızca {"error": {"code": ..., "message": ...}} dönmelidir.
    """
    res_404 = client.get("/v1/nonexistent-endpoint")
    assert res_404.status_code == 404
    body = res_404.json()
    assert set(body.keys()) == {"error"}
    assert set(body["error"].keys()) == {"code", "message"}
    assert "Traceback" not in str(body)
    assert "sqlalchemy" not in str(body).lower()
