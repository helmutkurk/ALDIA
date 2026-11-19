from typing import Annotated

from fastapi import APIRouter, Query

from app.categories import CATEGORIES
from app.dependencies import SessionDep
from app.models import Report
from app.report_queries import report_query
from app.schemas import Open311Filters, Open311Request, ReadFilters
from app.serialization import utc

router = APIRouter(prefix="/api/open311/v2")
SERVICE_NAMES = dict(CATEGORIES)


@router.get("/requests.json", response_model=list[Open311Request])
def list_requests(
    filters: Annotated[Open311Filters, Query()], session: SessionDep
) -> list[Open311Request]:
    query = report_query(
        ReadFilters(
            category=filters.service_code,
            status="verified",
            resolution="fixed" if filters.status == "closed" else None,
        )
    )
    if filters.status == "open":
        query = query.where(Report.resolution.in_(("open", "acknowledged")))
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
            status="closed" if row.resolution == "fixed" else "open",
            service_code=row.category,
            service_name=SERVICE_NAMES[row.category],
            description=row.note or "",
            lat=row.latitude,
            long=row.longitude,
            requested_datetime=utc(row.created_at),
            updated_datetime=utc(row.created_at),
            media_url=f"/api/reports/{row.id}/photo",
        )
        for row in rows
    ]
