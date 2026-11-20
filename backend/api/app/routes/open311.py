from typing import Annotated

from fastapi import APIRouter, Query

from app.categories import CATEGORIES, CATEGORY_GROUPS
from app.dependencies import SessionDep
from app.models import Report
from app.report_queries import report_query
from app.schemas import Open311Filters, Open311Request, Open311Service, ReadFilters
from app.serialization import utc
from app.state_machine import STATE_GROUPS

router = APIRouter(prefix="/api/open311/v2")
SERVICE_NAMES = dict(CATEGORIES)


@router.get("/services.json", response_model=list[Open311Service])
def list_services() -> list[Open311Service]:
    return [
        Open311Service(
            service_code=code,
            service_name=label,
            description=f"Reportes de {label.lower()}.",
            keywords=code,
            group=CATEGORY_GROUPS[code],
        )
        for code, label in CATEGORIES
    ]


@router.get("/requests.json", response_model=list[Open311Request])
def list_requests(
    filters: Annotated[Open311Filters, Query()], session: SessionDep
) -> list[Open311Request]:
    query = report_query(
        ReadFilters(
            category=filters.service_code,
            status="verified",
            include_old=True,
        )
    )
    if filters.status is not None:
        query = query.where(
            Report.state.in_(
                [
                    state
                    for state, group in STATE_GROUPS.items()
                    if (group in {"resolved", "closed"}) == (filters.status == "closed")
                ]
            )
        )
    if filters.start_date is not None:
        query = query.where(Report.created_at >= utc(filters.start_date))
    if filters.end_date is not None:
        query = query.where(Report.created_at <= utc(filters.end_date))
    rows = session.scalars(
        query.order_by(Report.created_at.desc(), Report.id.desc()).limit(1000)
    )
    return [
        Open311Request(
            service_request_id=str(row.id),
            status="closed"
            if STATE_GROUPS[row.state] in {"resolved", "closed"}
            else "open",
            service_code=row.category,
            service_name=SERVICE_NAMES[row.category],
            description=row.note or "",
            lat=row.latitude,
            long=row.longitude,
            requested_datetime=utc(row.created_at),
            updated_datetime=utc(row.state_changed_at),
            media_url=f"/api/reports/{row.id}/photo",
        )
        for row in rows
    ]
