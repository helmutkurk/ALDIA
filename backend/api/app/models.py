from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Uuid,
)
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
            "resolution IN ('open', 'acknowledged', 'fixed', 'closed')",
            name="ck_reports_resolution",
        ),
        Index("ix_reports_created_at", "created_at", "id"),
        Index("ix_reports_category_location", "category", "latitude", "longitude"),
        Index("ix_reports_status", "status"),
        Index("ix_reports_state", "state"),
        Index("ix_reports_category_state", "category", "state"),
        Index("ix_reports_location", "latitude", "longitude"),
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
    state: Mapped[str] = mapped_column(
        String(32),
        default="pendiente_verificacion",
        server_default="pendiente_verificacion",
    )
    state_changed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC)
    )
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    assignee: Mapped[str | None] = mapped_column(String(60))
    assigned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    duplicate_of: Mapped[UUID | None] = mapped_column(Uuid, ForeignKey("reports.id"))
    public_note: Mapped[str | None] = mapped_column(String(280))
    previous_state: Mapped[str | None] = mapped_column(String(32))


class ReportEvent(Base):
    __tablename__ = "report_events"
    __table_args__ = (Index("ix_report_events_report_at", "report_id", "at", "id"),)

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    report_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("reports.id"))
    actor_role: Mapped[str] = mapped_column(String(16))
    actor: Mapped[str] = mapped_column(
        String(80), default="system", server_default="system"
    )
    from_state: Mapped[str | None] = mapped_column(String(32))
    to_state: Mapped[str] = mapped_column(String(32))
    public_note: Mapped[str | None] = mapped_column(String(280))
    internal_note: Mapped[str | None] = mapped_column(String(500))
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"
    __table_args__ = (Index("ix_idempotency_records_created_at", "created_at"),)

    key: Mapped[UUID] = mapped_column(Uuid, primary_key=True)
    report_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("reports.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class StaffUser(Base):
    __tablename__ = "staff_users"
    __table_args__ = (
        CheckConstraint(
            "role IN ('operator', 'supervisor', 'admin')", name="ck_staff_users_role"
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    username: Mapped[str] = mapped_column(String(64), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(16))
    disabled: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0")
    failed_attempts: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class StaffSession(Base):
    __tablename__ = "staff_sessions"
    __table_args__ = (
        Index("ix_staff_sessions_user_id", "user_id"),
        Index("ix_staff_sessions_expires_at", "expires_at"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("staff_users.id"))
    signing_key: Mapped[str] = mapped_column(String(64))
    csrf_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class AuthEvent(Base):
    __tablename__ = "auth_events"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    actor: Mapped[str] = mapped_column(String(80))
    actor_role: Mapped[str] = mapped_column(String(16))
    action: Mapped[str] = mapped_column(String(32))
    target: Mapped[str | None] = mapped_column(String(64))
    at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC)
    )
