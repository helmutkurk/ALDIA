from datetime import UTC, datetime
from typing import cast

from app.models import Report
from app.schemas import ReportOut, Resolution, Status, Verification


def utc(value: datetime) -> datetime:
    # SQLite drops timezone metadata; production Postgres preserves it.
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def serialize(report: Report) -> ReportOut:
    return ReportOut(
        id=report.id,
        category=report.category,
        latitude=report.latitude,
        longitude=report.longitude,
        captured_at=utc(report.captured_at),
        created_at=utc(report.created_at),
        status=cast(Status, report.status),
        resolution=cast(Resolution, report.resolution),
        note=report.note,
        photo_url=f"/api/reports/{report.id}/photo",
        verification=Verification.model_validate(report.verification)
        if report.verification is not None
        else None,
    )
