from datetime import datetime
from uuid import UUID

from sqlalchemy import JSON, CheckConstraint, DateTime, Float, Index, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Report(Base):
    __tablename__ = "reports"
    __table_args__ = (
        CheckConstraint(
            "latitude >= -90 AND latitude <= 90", name="ck_reports_latitude"
        ),
        CheckConstraint(
            "longitude >= -180 AND longitude <= 180", name="ck_reports_longitude"
        ),
        CheckConstraint(
            "status IN ('pending', 'verified', 'rejected')", name="ck_reports_status"
        ),
        CheckConstraint(
            "resolution IN ('open', 'acknowledged', 'fixed')",
            name="ck_reports_resolution",
        ),
        Index("ix_reports_created_at", "created_at", "id"),
        Index("ix_reports_category_location", "category", "latitude", "longitude"),
        Index("ix_reports_status", "status"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True)
    category: Mapped[str] = mapped_column(String(32))
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    captured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(16))
    resolution: Mapped[str] = mapped_column(
        String(16), default="open", server_default="open"
    )
    note: Mapped[str | None] = mapped_column(String(280))
    phash: Mapped[str | None] = mapped_column(String(16))
    verification: Mapped[dict[str, object] | None] = mapped_column(
        JSON(none_as_null=True)
    )
