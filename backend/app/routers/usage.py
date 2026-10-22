from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import get_current_device
from app.models import Device
from app.schemas import UsageHistoryResponse, UsageRecordResponse, UsageUpsertRequest
from app.services.usage_service import get_usage_history, upsert_daily_usage

router = APIRouter(prefix="/v1/usage", tags=["usage"])


@router.post(
    "",
    response_model=UsageRecordResponse,
    summary="Günlük kullanım verisini kaydet veya güncelle (idempotent)",
)
def post_usage(
    payload: UsageUpsertRequest,
    device: Device = Depends(get_current_device),
    db: Session = Depends(get_db),
) -> UsageRecordResponse:
    """
    Cihazdan gelen günlük kullanım süresini ve en çok kullanılan uygulamaları kaydeder.
    Aynı gün (date) için tekrar gönderilirse mevcut kaydın üzerine yazar (idempotent).
    """
    record = upsert_daily_usage(db=db, device_id=device.id, payload=payload)
    return UsageRecordResponse.model_validate(record)


@router.get(
    "",
    response_model=UsageHistoryResponse,
    summary="Geçmiş kullanım kayıtlarını ve ortalamayı getir",
)
def get_usage(
    days: int = Query(default=7, ge=1, le=90, description="Kaç günlük geçmiş getirileceği"),
    device: Device = Depends(get_current_device),
    db: Session = Depends(get_db),
) -> UsageHistoryResponse:
    """
    Cihazın son `days` gün için kullanım kayıtlarını ve günlük ortalama süresini döndürür.
    """
    return get_usage_history(db=db, device_id=device.id, days=days)
