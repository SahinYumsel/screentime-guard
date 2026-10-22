from fastapi import APIRouter, Body, Depends, status
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.deps import generate_device_token
from app.models import Device, Rule, RuleMode
from app.schemas import DeviceCreate, DeviceRegisterResponse

router = APIRouter(prefix="/v1/devices", tags=["devices"])


@router.post(
    "",
    response_model=DeviceRegisterResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Yeni cihaz kaydı oluştur ve device_token üret",
)
def register_device(
    payload: DeviceCreate = Body(default_factory=DeviceCreate),
    db: Session = Depends(get_db),
) -> DeviceRegisterResponse:
    """
    Uygulamanın ilk açılışında cihazı kaydeder.
    Rastgele bir `token` üretir; veritabanında yalnızca SHA-256 hash'ini saklar.
    Ayrıca cihaz için varsayılan bir kural (Rule) oluşturur.
    """
    raw_token, token_digest = generate_device_token()

    device = Device(
        name=payload.name,
        token_hash=token_digest,
    )
    db.add(device)
    db.flush()  # device.id (UUID) üretilmesi için

    default_rule = Rule(
        device_id=device.id,
        daily_limit_min=settings.default_daily_limit_min,
        cutoff_start=settings.default_cutoff_start,
        cutoff_end=settings.default_cutoff_end,
        mode=RuleMode(settings.default_rule_mode),
    )
    db.add(default_rule)
    db.commit()
    db.refresh(device)

    return DeviceRegisterResponse(
        device_id=device.id,
        token=raw_token,
        name=device.name,
        created_at=device.created_at,
    )
