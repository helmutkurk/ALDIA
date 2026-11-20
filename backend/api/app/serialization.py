from datetime import UTC, datetime
from typing import Literal, cast

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Report, ReportEvent
from app.schemas import EventOut, ReportOut, Resolution, Status, Verification
from app.state_machine import STATE_GROUPS, State, StateGroup

LiteralRole = Literal["system", "operator", "supervisor", "admin"]


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
        state=cast(State, report.state),
        state_group=cast(StateGroup, STATE_GROUPS[report.state]),
        state_changed_at=utc(report.state_changed_at),
        verified_at=utc(report.verified_at) if report.verified_at else None,
        resolved_at=utc(report.resolved_at) if report.resolved_at else None,
        closed_at=utc(report.closed_at) if report.closed_at else None,
        assignee=report.assignee,
        assigned_at=utc(report.assigned_at) if report.assigned_at else None,
        duplicate_of=report.duplicate_of,
        public_note=report.public_note,
        verification=Verification.model_validate(report.verification)
        if report.verification is not None
        else None,
    )


def detail(report: Report, session: Session, *, staff: bool = False) -> ReportOut:
    result = serialize(report)
    events = session.scalars(
        select(ReportEvent)
        .where(ReportEvent.report_id == report.id)
        .order_by(ReportEvent.at, ReportEvent.id)
    )
    result.events = []
    for event in events:
        item = EventOut(
            at=utc(event.at),
            actor=event.actor,
            actor_role=cast("LiteralRole", event.actor_role),
            from_state=cast(State | None, event.from_state),
            to_state=cast(State, event.to_state),
            public_note=event.public_note,
        )
        if staff:
            item.internal_note = event.internal_note
        result.events.append(item)
    return result
