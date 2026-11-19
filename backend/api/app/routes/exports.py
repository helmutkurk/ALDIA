import csv
from datetime import UTC, datetime
from io import StringIO
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Response
from sqlalchemy import func, select

from app.dependencies import SessionDep
from app.models import Report
from app.report_queries import ordered_query, report_query
from app.schemas import ExportFilters
from app.serialization import utc
from app.state_machine import OPEN_STATES

router = APIRouter(prefix="/api")
CSV_FIELDS = (
    "id",
    "created_at",
    "verified_at",
    "category",
    "state",
    "state_changed_at",
    "resolved_at",
    "latitude",
    "longitude",
    "assignee",
    "verifier_status",
    "duplicates_count",
    "days_open",
    "link",
)


def safe_cell(value: object) -> str:
    """Neutralize spreadsheet formulas in text cells, preserving numeric values."""
    if value is None:
        return ""
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    return (
        "'" + text
        if text.lstrip().startswith(("=", "+", "-", "@"))
        or text.startswith(("\t", "\r", "\n"))
        else text
    )


def timestamp(value: datetime | None) -> str:
    return utc(value).isoformat().replace("+00:00", "Z") if value else ""


@router.get("/reports.csv", response_class=Response)
def export_reports(
    filters: Annotated[ExportFilters, Query()], session: SessionDep
) -> Response:
    rows = session.scalars(
        ordered_query(report_query(filters), filters.sort).limit(5000)
    )
    duplicates: dict[UUID | None, int] = {
        master: count
        for master, count in session.execute(
            select(Report.duplicate_of, func.count())
            .where(Report.duplicate_of.is_not(None), Report.state == "duplicado")
            .group_by(Report.duplicate_of)
        )
    }
    output = StringIO(newline="")
    output.write("\ufeff")
    writer = csv.writer(
        output, delimiter=";" if filters.delimiter == "semicolon" else ","
    )
    writer.writerow(CSV_FIELDS)
    now = datetime.now(UTC)
    for row in rows:
        stop = (
            row.resolved_at
            or row.closed_at
            or (now if row.state in OPEN_STATES else None)
        )
        days_open = (
            (utc(stop) - utc(row.verified_at)).total_seconds() / 86400
            if stop and row.verified_at
            else None
        )
        writer.writerow(
            safe_cell(value)
            for value in (
                row.id,
                timestamp(row.created_at),
                timestamp(row.verified_at),
                row.category,
                row.state,
                timestamp(row.state_changed_at),
                timestamp(row.resolved_at),
                row.latitude,
                row.longitude,
                row.assignee,
                row.status,
                duplicates.get(row.id, 0),
                days_open,
                f"/api/reports/{row.id}",
            )
        )
    return Response(
        output.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": "attachment; filename=aldia-reports.csv"},
    )
