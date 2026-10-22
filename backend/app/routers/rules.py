from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.deps import get_current_device
from app.models import Device, Rule, RuleMode, utc_now
from app.schemas import RuleResponse, RuleUpdate

router = APIRouter(prefix="/v1/rules", tags=["rules"])


@router.get(
    "",
    response_model=RuleResponse,
    summary="Cihazın mevcut ekran süresi kuralını getir",
)
def get_rule(
    device: Device = Depends(get_current_device),
    db: Session = Depends(get_db),
) -> RuleResponse:
    """
    X-Device-Token ile doğrulanan cihazın aktif kuralını döndürür.
    Eğer kural henüz yoksa varsayılan kuralı oluşturup döndürür.
    """
    stmt = select(Rule).where(Rule.device_id == device.id)
    rule = db.execute(stmt).scalar_one_or_none()

    if rule is None:
        rule = Rule(
            device_id=device.id,
            daily_limit_min=settings.default_daily_limit_min,
            cutoff_start=settings.default_cutoff_start,
            cutoff_end=settings.default_cutoff_end,
            mode=RuleMode(settings.default_rule_mode),
        )
        db.add(rule)
        db.commit()
        db.refresh(rule)

    return RuleResponse.model_validate(rule)


@router.put(
    "",
    response_model=RuleResponse,
    summary="Cihazın ekran süresi kuralını oluştur veya güncelle",
)
def update_rule(
    payload: RuleUpdate,
    device: Device = Depends(get_current_device),
    db: Session = Depends(get_db),
) -> RuleResponse:
    """
    Cihazın günlük limitini, kesme saat aralığını (cutoff_start - cutoff_end)
    ve uyarı modunu (notify / overlay) günceller.
    """
    stmt = select(Rule).where(Rule.device_id == device.id)
    rule = db.execute(stmt).scalar_one_or_none()

    if rule is None:
        rule = Rule(
            device_id=device.id,
            daily_limit_min=payload.daily_limit_min,
            cutoff_start=payload.cutoff_start,
            cutoff_end=payload.cutoff_end,
            mode=payload.mode,
            updated_at=utc_now(),
        )
        db.add(rule)
    else:
        rule.daily_limit_min = payload.daily_limit_min
        rule.cutoff_start = payload.cutoff_start
        rule.cutoff_end = payload.cutoff_end
        rule.mode = payload.mode
        rule.updated_at = utc_now()

    db.commit()
    db.refresh(rule)
    return RuleResponse.model_validate(rule)
