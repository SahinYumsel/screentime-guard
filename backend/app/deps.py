import hashlib
import secrets
from typing import Annotated

from fastapi import Depends, Header, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Device


class AppError(Exception):
    """Standart hata formatı ({"error": {"code": ..., "message": ...}}) üreten özel istisna sınıfı."""

    def __init__(self, status_code: int, code: str, message: str) -> None:
        self.status_code = status_code
        self.code = code
        self.message = message
        super().__init__(message)


def hash_token(raw_token: str) -> str:
    """Ham cihaz token'ının SHA-256 özetini (hex) döndürür."""
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def generate_device_token() -> tuple[str, str]:
    """Rastgele güvenli bir token ve onun SHA-256 hash değerini üretir."""
    raw_token = secrets.token_urlsafe(32)
    return raw_token, hash_token(raw_token)


def get_current_device(
    x_device_token: Annotated[str | None, Header(alias="X-Device-Token")] = None,
    db: Session = Depends(get_db),
) -> Device:
    """
    X-Device-Token HTTP başlığını doğrular ve ilgili Device kaydını döndürür.
    Token eksik veya geçersizse 401 INVALID_TOKEN fırlatır.
    """
    if not x_device_token or not x_device_token.strip():
        raise AppError(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="INVALID_TOKEN",
            message="X-Device-Token başlığı eksik veya boş.",
        )

    token_digest = hash_token(x_device_token.strip())
    stmt = select(Device).where(Device.token_hash == token_digest)
    device = db.execute(stmt).scalar_one_or_none()

    if device is None:
        raise AppError(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="INVALID_TOKEN",
            message="Geçersiz cihaz token'ı.",
        )

    return device
