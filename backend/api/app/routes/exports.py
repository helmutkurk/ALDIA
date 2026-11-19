import csv
from io import StringIO
from typing import Annotated

from fastapi import APIRouter, Query, Response

from app.dependencies import SessionDep
from app.models import Report
from app.report_queries import report_query
from app.schemas import ReadFilters
from app.serialization import utc

router = APIRouter(prefix="/api")
CSV_FIELDS = (
    "id",
    "category",
    "latitude",
    "longitude",
    "captured_at",
    "created_at",
    "status",
    "resolution",
    "photo_url",
)


def safe_cell(value: object) -> str:
    """Neutralize spreadsheet formulas in text cells; numbers are written as is."""
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    return "'" + text if text.startswith(("=", "+", "-", "@")) else text


@router.get("/reports.csv", response_class=Response)
def export_reports(
    filters: Annotated[ReadFilters, Query()], session: SessionDep
) -> Response:
    rows = session.scalars(
        report_query(filters)
        .order_by(Report.created_at.desc(), Report.id.desc())
        .limit(5000)
    )
    output = StringIO(newline="")
    writer = csv.writer(output)
    writer.writerow(CSV_FIELDS)
    for row in rows:
        writer.writerow(
            safe_cell(value)
            for value in (
                row.id,
                row.category,
                row.latitude,
                row.longitude,
                utc(row.captured_at).isoformat().replace("+00:00", "Z"),
                utc(row.created_at).isoformat().replace("+00:00", "Z"),
                row.status,
                row.resolution,
                f"/api/reports/{row.id}/photo",
            )
        )
    return Response(
        output.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": "attachment; filename=aldia-reports.csv"},
    )
