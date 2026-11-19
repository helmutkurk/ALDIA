from typing import Annotated, get_args

from fastapi import APIRouter, Query
from sqlalchemy import func, select

from app.categories import CATEGORY_IDS
from app.dependencies import SessionDep
from app.report_queries import report_query
from app.schemas import ReadFilters, Resolution, StatsOut, Status

router = APIRouter(prefix="/api")


@router.get("/stats", response_model=StatsOut)
def get_stats(
    filters: Annotated[ReadFilters, Query()], session: SessionDep
) -> StatsOut:
    counts = StatsOut(
        total=0,
        by_category=dict.fromkeys(CATEGORY_IDS, 0),
        by_status=dict.fromkeys(get_args(Status), 0),
        by_resolution=dict.fromkeys(get_args(Resolution), 0),
    )
    rows = report_query(filters).subquery()
    # One grouped query keeps all totals consistent without loading reports.
    for category, status, resolution, count in session.execute(
        select(
            rows.c.category, rows.c.status, rows.c.resolution, func.count()
        ).group_by(rows.c.category, rows.c.status, rows.c.resolution)
    ):
        counts.total += count
        counts.by_category[category] += count
        counts.by_status[status] += count
        counts.by_resolution[resolution] += count
    return counts
