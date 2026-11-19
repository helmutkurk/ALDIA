"""Shared visibility, filters, period boundaries, ordering and pagination."""

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session

from app.models import Report, ReportEvent
from app.schemas import ReadFilters, parse_bbox
from app.state_machine import STATE_GROUPS

MUNICIPAL_TZ = ZoneInfo("America/Guatemala")


def period_bounds(
    filters: ReadFilters, now: datetime
) -> tuple[datetime | None, datetime | None]:
    start = (
        datetime.combine(filters.created_from, time.min, MUNICIPAL_TZ).astimezone(UTC)
        if filters.created_from
        else None
        if filters.include_old
        else now - timedelta(days=30)
    )
    end = (
        datetime.combine(
            filters.created_to + timedelta(days=1), time.min, MUNICIPAL_TZ
        ).astimezone(UTC)
        if filters.created_to and filters.created_to < date.max
        else None
    )
    return start, end


def report_query(
    filters: ReadFilters,
    *,
    include_hidden: bool = False,
    apply_period: bool = True,
    now: datetime | None = None,
) -> Select[tuple[Report]]:
    query = select(Report)
    if not include_hidden:
        query = query.where(Report.state != "oculto")
    for name in ("category", "status", "resolution", "state", "assignee"):
        value = getattr(filters, name)
        if value is not None:
            query = query.where(getattr(Report, name) == value)
    if filters.state_group is not None:
        query = query.where(
            Report.state.in_(
                [
                    state
                    for state, group in STATE_GROUPS.items()
                    if group == filters.state_group
                ]
            )
        )
    if filters.bbox is not None:
        west, south, east, north = parse_bbox(filters.bbox)
        query = query.where(
            Report.longitude.between(west, east), Report.latitude.between(south, north)
        )
    if apply_period:
        start, end = period_bounds(filters, now or datetime.now(UTC))
        if start is not None:
            query = query.where(Report.created_at >= start)
        if end is not None:
            query = query.where(Report.created_at < end)
    return query


def ordered_query(query: Select[tuple[Report]], sort: str) -> Select[tuple[Report]]:
    if sort == "oldest":
        return query.order_by(Report.created_at, Report.id)
    if sort == "age_in_state":
        return query.order_by(Report.state_changed_at, Report.id)
    if sort == "updated":
        # Moderation timestamps and private-only events do not reveal staff activity.
        updated = (
            select(func.max(ReportEvent.at))
            .where(
                ReportEvent.report_id == Report.id,
                ReportEvent.to_state != "oculto",
                ReportEvent.from_state.is_distinct_from("oculto"),
                (ReportEvent.internal_note.is_(None))
                | (func.trim(func.coalesce(ReportEvent.public_note, "")) != ""),
            )
            .correlate(Report)
            .scalar_subquery()
        )
        return query.order_by(
            func.coalesce(updated, Report.created_at).desc(), Report.id.desc()
        )
    return query.order_by(Report.created_at.desc(), Report.id.desc())


def page(
    session: Session, query: Select[tuple[Report]], limit: int, offset: int
) -> tuple[list[Report], int]:
    total = (
        session.scalar(
            select(func.count()).select_from(query.order_by(None).subquery())
        )
        or 0
    )
    return list(session.scalars(query.limit(limit).offset(offset))), total


def find_report(
    report_id: UUID, session: Session, *, staff: bool = False, lock: bool = False
) -> Report:
    query = select(Report).where(Report.id == report_id)
    if lock:
        query = query.with_for_update()
    report = session.scalar(query)
    if report is None or (report.state == "oculto" and not staff):
        raise HTTPException(404)
    return report
