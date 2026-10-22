import datetime as dt
import re
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models import RuleMode

TIME_HHMM_REGEX = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


# --- Ortak Hata Şemaları ---
class ErrorDetail(BaseModel):
    code: str
    message: str


class ErrorResponse(BaseModel):
    error: ErrorDetail


# --- Cihaz (Device) Şemaları ---
class DeviceCreate(BaseModel):
    name: str = Field(
        default="Android Device",
        min_length=1,
        max_length=100,
        description="Cihazın okunabilir adı (örn. Pixel 7, Samsung S23)",
    )


class DeviceRegisterResponse(BaseModel):
    device_id: str
    token: str
    name: str
    created_at: dt.datetime


# --- Kural (Rule) Şemaları ---
class RuleUpdate(BaseModel):
    daily_limit_min: int = Field(
        ...,
        ge=1,
        le=1440,
        description="Günlük ekran kullanım limiti (dakika cinsinden, 1-1440 arası)",
    )
    cutoff_start: str = Field(
        ...,
        description="Kesme başlangıç saati (HH:MM formatında, örn. 23:00)",
    )
    cutoff_end: str = Field(
        ...,
        description="Kesme bitiş saati (HH:MM formatında, örn. 06:00)",
    )
    mode: RuleMode = Field(
        ...,
        description="Uyarı modu: 'notify' veya 'overlay'",
    )

    @field_validator("cutoff_start", "cutoff_end")
    @classmethod
    def validate_hhmm(cls, value: str) -> str:
        if not TIME_HHMM_REGEX.match(value):
            raise ValueError("Saat formatı HH:MM (00:00 - 23:59) olmalıdır.")
        return value


class RuleResponse(BaseModel):
    device_id: str
    daily_limit_min: int
    cutoff_start: str
    cutoff_end: str
    mode: RuleMode
    updated_at: dt.datetime

    model_config = ConfigDict(from_attributes=True)


# --- Kullanım (DailyUsage) Şemaları ---
class TopAppItem(BaseModel):
    package: str = Field(..., min_length=1, max_length=255)
    minutes: int = Field(..., ge=0, le=1440)


class UsageUpsertRequest(BaseModel):
    date: dt.date = Field(..., description="Kullanım tarihi (YYYY-MM-DD)")
    total_minutes: int = Field(
        ...,
        ge=0,
        le=1440,
        description="O günkü toplam ekran süresi (dakika)",
    )
    top_apps: list[TopAppItem] = Field(
        default_factory=list,
        max_length=20,
        description="En çok kullanılan uygulamalar listesi (en fazla 20 kayıt)",
    )


class UsageRecordResponse(BaseModel):
    device_id: str
    date: dt.date
    total_minutes: int
    top_apps: list[TopAppItem]
    synced_at: dt.datetime

    model_config = ConfigDict(from_attributes=True)


class UsageHistoryResponse(BaseModel):
    days: int
    average_minutes: float
    items: list[UsageRecordResponse]
