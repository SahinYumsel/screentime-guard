import datetime as dt
import enum
from typing import Any
import uuid

from sqlalchemy import JSON, Date, DateTime, Enum, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


class RuleMode(str, enum.Enum):
    """Uyarı gösterim modu: Bildirim veya Ekran Üstü Uyarı (Overlay)."""
    notify = "notify"
    overlay = "overlay"


class Device(Base):
    """Kayıtlı Android cihaz modeli."""

    __tablename__ = "devices"

    id: Mapped[str] = mapped_column(
        String(36),
        primary_key=True,
        default=lambda: str(uuid.uuid4()),
    )
    token_hash: Mapped[str] = mapped_column(
        String(64),
        unique=True,
        index=True,
        nullable=False,
    )
    name: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
        default="Android Device",
    )
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True),
        default=utc_now,
        nullable=False,
    )

    rule: Mapped["Rule"] = relationship(
        "Rule",
        back_populates="device",
        uselist=False,
        cascade="all, delete-orphan",
    )
    usages: Mapped[list["DailyUsage"]] = relationship(
        "DailyUsage",
        back_populates="device",
        cascade="all, delete-orphan",
    )


class Rule(Base):
    """Cihaz başına tanımlanan günlük süre limiti ve kesme saati (cutoff) kuralı."""

    __tablename__ = "rules"

    device_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("devices.id", ondelete="CASCADE"),
        primary_key=True,
    )
    daily_limit_min: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=120,
    )
    cutoff_start: Mapped[str] = mapped_column(
        String(5),
        nullable=False,
        default="23:00",
    )
    cutoff_end: Mapped[str] = mapped_column(
        String(5),
        nullable=False,
        default="06:00",
    )
    mode: Mapped[RuleMode] = mapped_column(
        Enum(RuleMode),
        nullable=False,
        default=RuleMode.notify,
    )
    updated_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )

    device: Mapped["Device"] = relationship("Device", back_populates="rule")


class DailyUsage(Base):
    """Cihazın belirli bir güne ait toplam kullanım süresi ve en çok kullanılan uygulamaları."""

    __tablename__ = "daily_usage"
    __table_args__ = (
        UniqueConstraint("device_id", "date", name="uq_daily_usage_device_date"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("devices.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    date: Mapped[dt.date] = mapped_column(Date, nullable=False, index=True)
    total_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    top_apps: Mapped[list[dict[str, Any]]] = mapped_column(
        JSON,
        nullable=False,
        default=list,
    )
    synced_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True),
        default=utc_now,
        nullable=False,
    )

    device: Mapped["Device"] = relationship("Device", back_populates="usages")
