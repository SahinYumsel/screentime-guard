from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import DailyUsage, utc_now
from app.schemas import UsageHistoryResponse, UsageRecordResponse, UsageUpsertRequest


def upsert_daily_usage(
    db: Session,
    device_id: str,
    payload: UsageUpsertRequest,
) -> DailyUsage:
    """
    Günlük kullanım verisini idempotent olarak kaydeder veya günceller.
    Aynı (device_id, date) için kayıt varsa üzerine yazar, yoksa yeni kayıt oluşturur.
    """
    stmt = select(DailyUsage).where(
        DailyUsage.device_id == device_id,
        DailyUsage.date == payload.date,
    )
    record = db.execute(stmt).scalar_one_or_none()

    serialized_apps = [app.model_dump() for app in payload.top_apps]
    now = utc_now()

    if record is not None:
        record.total_minutes = payload.total_minutes
        record.top_apps = serialized_apps
        record.synced_at = now
    else:
        record = DailyUsage(
            device_id=device_id,
            date=payload.date,
            total_minutes=payload.total_minutes,
            top_apps=serialized_apps,
            synced_at=now,
        )
        db.add(record)

    db.commit()
    db.refresh(record)
    return record


def get_usage_history(
    db: Session,
    device_id: str,
    days: int = 7,
) -> UsageHistoryResponse:
    """
    Cihazın son N günlük kullanım geçmişini ve günlük ortalama süresini döndürür.
    """
    stmt = (
        select(DailyUsage)
        .where(DailyUsage.device_id == device_id)
        .order_by(DailyUsage.date.desc())
        .limit(days)
    )
    records = list(db.execute(stmt).scalars().all())

    if records:
        avg_minutes = round(sum(r.total_minutes for r in records) / len(records), 1)
    else:
        avg_minutes = 0.0

    items = [UsageRecordResponse.model_validate(r) for r in records]
    return UsageHistoryResponse(
        days=days,
        average_minutes=avg_minutes,
        items=items,
    )
