"""Dashboard formulas from the binding clean-room behavior specification §3."""

from collections import defaultdict
from datetime import UTC, datetime
from statistics import mean, median
from typing import Annotated, get_args

from fastapi import APIRouter, Query
from sqlalchemy import select

from app.categories import CATEGORY_IDS, SLA_HOURS
from app.dependencies import SessionDep
from app.models import Report, ReportEvent
from app.report_queries import MUNICIPAL_TZ, period_bounds, report_query
from app.schemas import (
    DurationStats,
    ReadFilters,
    Resolution,
    ResolutionStats,
    StatsOut,
    Status,
    WeeklyStats,
)
from app.serialization import utc
from app.state_machine import OPEN_STATES, STATE_GROUPS

router = APIRouter(prefix="/api")


def percentile90(values: list[float]) -> float | None:
    """Linear interpolation at (n - 1) * 0.9, including singleton samples."""
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * 0.9
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def durations(values: list[float]) -> DurationStats:
    return DurationStats(
        median=median(values) if values else None,
        p90=percentile90(values),
        n=len(values),
    )


@router.get("/stats", response_model=StatsOut)
def get_stats(
    filters: Annotated[ReadFilters, Query()], session: SessionDep
) -> StatsOut:
    now = datetime.now(UTC)
    start, end = period_bounds(filters, now)

    def in_period(value: datetime | None) -> bool:
        return (
            value is not None
            and (start is None or utc(value) >= start)
            and (end is None or utc(value) < end)
        )

    base = report_query(filters, apply_period=False)
    reports = list(session.scalars(base))
    cohort = [r for r in reports if in_period(r.created_at)]
    resolved = [
        r for r in reports if r.state == "resuelto" and in_period(r.resolved_at)
    ]
    open_reports = [r for r in cohort if r.state in OPEN_STATES]
    received = sum(r.verified_at is not None for r in cohort)
    denominator = received - sum(
        r.state in {"duplicado", "fuera_de_competencia"} for r in cohort
    )
    resolution_times = [
        (utc(r.resolved_at) - utc(r.verified_at)).total_seconds() / 3600
        for r in resolved
        if r.resolved_at is not None and r.verified_at is not None
    ]
    first_responses: dict[object, datetime] = {}
    for event in session.scalars(
        select(ReportEvent)
        .where(
            ReportEvent.report_id.in_(base.with_only_columns(Report.id)),
            ReportEvent.actor_role != "system",
        )
        .order_by(ReportEvent.at, ReportEvent.id)
    ):
        if event.from_state != event.to_state or (
            event.public_note and event.public_note.strip()
        ):
            first_responses.setdefault(event.report_id, utc(event.at))
    response_times = [
        (first_responses[r.id] - utc(r.verified_at)).total_seconds() / 3600
        for r in cohort
        if r.verified_at is not None and r.id in first_responses
    ]
    ages = {"0-2": 0, "3-7": 0, "8-30": 0, ">30": 0}
    overdue = 0
    for report in open_reports:
        if report.verified_at is None:
            continue
        age_hours = (now - utc(report.verified_at)).total_seconds() / 3600
        days = int(age_hours // 24)
        ages[
            "0-2"
            if days <= 2
            else "3-7"
            if days <= 7
            else "8-30"
            if days <= 30
            else ">30"
        ] += 1
        overdue += age_hours > SLA_HOURS[report.category]
    sla_met = sum(
        r.verified_at is not None
        and r.resolved_at is not None
        and (utc(r.resolved_at) - utc(r.verified_at)).total_seconds() / 3600
        <= SLA_HOURS[r.category]
        for r in resolved
    )
    by_category = dict.fromkeys(CATEGORY_IDS, 0)
    by_status = dict.fromkeys(get_args(Status), 0)
    by_resolution = dict.fromkeys(get_args(Resolution), 0)
    by_state = dict.fromkeys(STATE_GROUPS, 0)
    by_group = dict.fromkeys(STATE_GROUPS.values(), 0)
    for r in cohort:
        by_category[r.category] += 1
        by_status[r.status] += 1
        by_resolution[r.resolution] += 1
        by_state[r.state] += 1
        by_group[STATE_GROUPS[r.state]] += 1
    weekly: dict[str, list[int]] = defaultdict(lambda: [0, 0])

    def week(value: datetime) -> str:
        year, number, _ = utc(value).astimezone(MUNICIPAL_TZ).isocalendar()
        return f"{year}-W{number:02d}"

    for r in cohort:
        if r.verified_at is not None:
            weekly[week(r.created_at)][0] += 1
    for r in resolved:
        if r.resolved_at is not None:
            weekly[week(r.resolved_at)][1] += 1
    return StatsOut(
        total=len(cohort),
        by_category=by_category,
        by_status=by_status,
        by_resolution=by_resolution,
        recibidos=received,
        rechazados_verificador=sum(r.state == "rechazado_verificador" for r in cohort),
        abiertos=len(open_reports),
        resueltos=len(resolved),
        cerrados_sin_solucion=sum(
            r.state in {"no_procede", "fuera_de_competencia", "duplicado"}
            and in_period(r.closed_at)
            for r in reports
        ),
        tasa_resolucion=100
        * sum(r.state == "resuelto" and r.resolved_at is not None for r in cohort)
        / denominator
        if denominator
        else None,
        tasa_resolucion_n=denominator,
        resolucion_horas=ResolutionStats(
            **durations(resolution_times).model_dump(),
            mean=mean(resolution_times) if resolution_times else None,
        ),
        primera_respuesta_horas=durations(response_times),
        antiguedad_abiertos=ages,
        sla_cumplido=sla_met / len(resolved) if resolved else None,
        vencidos=overdue,
        by_state=by_state,
        by_state_group=by_group,
        weekly=[
            WeeklyStats(week=w, recibidos=v[0], resueltos=v[1])
            for w, v in sorted(weekly.items())
        ],
    )
