"""Lightweight map and triage reads, declared before UUID routes."""

import math
from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.dependencies import OptionalStaffDep, SessionDep, StaffDep
from app.models import Report
from app.report_queries import MUNICIPAL_TZ, find_report, page, report_query
from app.schemas import (
    Cluster,
    ClusterFilters,
    ClustersOut,
    NearbyFilters,
    NearbyItem,
    NearbyOut,
    QueueFilters,
    QueueItem,
    QueueOut,
    ReadFilters,
)
from app.serialization import serialize, utc
from app.services.duplicates import EARTH_RADIUS_METRES, distance_metres
from app.state_machine import OPEN_STATES

router = APIRouter(prefix="/api")


def nearby_reports(
    session: Session,
    latitude: float,
    longitude: float,
    category: str,
    radius: float,
    exclude: UUID | None = None,
) -> NearbyOut:
    angular = radius / EARTH_RADIUS_METRES
    delta_lat = math.degrees(angular)
    # Duplicate suggestions look back 30 days (contract), not the 90-day list default.
    since = (datetime.now(UTC) - timedelta(days=30)).astimezone(MUNICIPAL_TZ).date()
    query = report_query(
        ReadFilters(category=category, status="verified", created_from=since)
    ).where(
        Report.state.in_(OPEN_STATES),
        Report.latitude.between(
            max(-90, latitude - delta_lat), min(90, latitude + delta_lat)
        ),
    )
    # A circle touching a pole spans all longitudes. Else handle date-line wrap.
    if abs(latitude) + delta_lat < 90:
        delta_lon = math.degrees(
            math.asin(min(1.0, math.sin(angular) / math.cos(math.radians(latitude))))
        )
        west, east = longitude - delta_lon, longitude + delta_lon
        if west < -180:
            query = query.where(
                or_(Report.longitude >= west + 360, Report.longitude <= east)
            )
        elif east > 180:
            query = query.where(
                or_(Report.longitude >= west, Report.longitude <= east - 360)
            )
        else:
            query = query.where(Report.longitude.between(west, east))
    if exclude is not None:
        query = query.where(Report.id != exclude)
    candidates = []
    for report in session.scalars(query):
        distance = distance_metres(
            latitude, longitude, report.latitude, report.longitude
        )
        if distance <= radius:
            candidates.append((distance, str(report.id), report))
    candidates.sort(key=lambda item: (item[0], item[1]))
    return NearbyOut(
        items=[
            NearbyItem(
                **serialize(row).model_dump(exclude_unset=True),
                thumbnail_url=f"/api/reports/{row.id}/photo",
                distance_m=distance,
            )
            for distance, _id, row in candidates[:10]
        ]
    )


@router.get(
    "/reports/nearby", response_model=NearbyOut, response_model_exclude_unset=True
)
def nearby(
    filters: Annotated[NearbyFilters, Query()], session: SessionDep
) -> NearbyOut:
    return nearby_reports(
        session, filters.lat, filters.lon, filters.category, filters.radius_m
    )


@router.get(
    "/reports/{report_id}/nearby",
    response_model=NearbyOut,
    response_model_exclude_unset=True,
)
def report_nearby(
    report_id: UUID, session: SessionDep, role: OptionalStaffDep
) -> NearbyOut:
    report = find_report(report_id, session, staff=role is not None)
    return nearby_reports(
        session,
        report.latitude,
        report.longitude,
        report.category,
        100,
        exclude=report.id,
    )


@router.get("/reports/clusters", response_model=ClustersOut)
def clusters(
    filters: Annotated[ClusterFilters, Query()], session: SessionDep
) -> ClustersOut:
    # Anchor the grid globally so panning does not move cell boundaries.
    cell_size = 360.0 / (2**filters.zoom)
    cells: dict[tuple[float, float] | tuple[UUID], list[Report]] = {}
    total = 0
    for report in session.scalars(report_query(filters).order_by(Report.id)):
        total += 1
        key: tuple[float, float] | tuple[UUID] = (
            (report.id,)
            if filters.zoom >= 17
            else (
                math.floor((report.longitude + 180) / cell_size),
                math.floor((report.latitude + 90) / cell_size),
            )
        )
        cells.setdefault(key, []).append(report)
    result = [
        Cluster(
            lat=sum(r.latitude for r in rows) / len(rows),
            lon=sum(r.longitude for r in rows) / len(rows),
            count=len(rows),
            ids=[r.id for r in rows[:5]],
        )
        for rows in cells.values()
    ]
    return ClustersOut(clusters=result[:500], total=total)


@router.get("/queue", response_model=QueueOut, response_model_exclude_unset=True)
def queue(
    filters: Annotated[QueueFilters, Query()], session: SessionDep, role: StaffDep
) -> QueueOut:
    query = report_query(filters)
    if filters.tab == "review":
        query = query.where(Report.state == "nuevo", Report.assignee.is_(None))
    else:
        query = query.where(Report.state == "rechazado_verificador")
    rows, total = page(
        session,
        query.order_by(Report.verified_at, Report.id),
        filters.limit,
        filters.offset,
    )
    now = datetime.now(UTC)
    return QueueOut(
        items=[
            QueueItem(
                **serialize(row).model_dump(exclude_unset=True),
                age_hours=(now - utc(row.verified_at)).total_seconds() / 3600
                if row.verified_at
                else None,
            )
            for row in rows
        ],
        total=total,
        limit=filters.limit,
        offset=filters.offset,
    )
