from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import FileResponse
from pydantic import ValidationError
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool
from starlette.datastructures import UploadFile

from app.dependencies import Services, ServicesDep, SessionDep
from app.models import Report
from app.report_queries import report_query
from app.schemas import (
    Check,
    ReportCreate,
    ReportFilters,
    ReportList,
    ReportOut,
    Verification,
)
from app.serialization import serialize
from app.services.duplicates import is_duplicate

router = APIRouter(prefix="/api/reports")


def create_report(data: ReportCreate, content: bytes, services: Services) -> ReportOut:
    try:
        clean = services.storage.prepare(content)
    except ValueError as exc:
        raise HTTPException(422) from exc
    result = services.verifier.verify(clean, data)
    report_id = uuid4()
    with services.database.sessions() as session:
        # Serialize duplicate decisions on Postgres across processes. This
        # transaction lock also works for simultaneous first submissions.
        # SQLite is the single-process test backend, not a deployment target.
        if (
            result is not None
            and session.bind is not None
            and session.bind.dialect.name == "postgresql"
        ):
            session.execute(text("SELECT pg_advisory_xact_lock(219773001)"))
        verification: Verification | None = None
        if result is not None:
            duplicate = is_duplicate(
                session, data.category, data.latitude, data.longitude, result.phash
            )
            verification = Verification(
                passed=result.passed and not duplicate,
                mode=result.mode,
                checks=[
                    *result.checks,
                    Check(
                        name="duplicate",
                        passed=not duplicate,
                        detail="duplicate nearby"
                        if duplicate
                        else "no nearby duplicate",
                    ),
                ],
            )
        report = Report(
            id=report_id,
            category=data.category,
            latitude=data.latitude,
            longitude=data.longitude,
            captured_at=data.captured_at,
            created_at=datetime.now(UTC),
            note=data.note,
            status="pending"
            if verification is None
            else "verified"
            if verification.passed
            else "rejected",
            phash=None if result is None else result.phash,
            verification=None if verification is None else verification.model_dump(),
        )
        session.add(report)
        services.storage.save(report_id, clean)
        try:
            # Commit inside the cleanup guard, so DB failures remove the file.
            session.commit()
        except Exception:
            services.storage.delete(report_id)
            raise
    return serialize(report)


@router.post("", status_code=201, response_model=ReportOut)
async def post_report(request: Request, services: ServicesDep) -> ReportOut:
    async with request.form(max_files=2, max_fields=16, max_part_size=4096) as form:
        if len(form.multi_items()) != len(form):
            raise HTTPException(422)
        photo = form.get("photo")
        if not isinstance(photo, UploadFile):
            raise HTTPException(422)
        values = {key: value for key, value in form.items() if key != "photo"}
        if any(not isinstance(value, str) for value in values.values()):
            raise HTTPException(422)
        try:
            parsed: dict[str, object] = dict(values)
            for key in ("latitude", "longitude"):
                if key in parsed:
                    parsed[key] = float(str(parsed[key]))
            if "captured_at" in parsed:
                parsed["captured_at"] = datetime.fromisoformat(
                    str(parsed["captured_at"])
                )
            data = ReportCreate.model_validate(parsed)
        except (ValueError, ValidationError) as exc:
            raise HTTPException(422) from exc
        content = await photo.read(services.settings.max_upload_bytes + 1)
        if len(content) > services.settings.max_upload_bytes:
            raise HTTPException(413)
        return await run_in_threadpool(create_report, data, content, services)


@router.get("", response_model=ReportList)
def list_reports(
    filters: Annotated[ReportFilters, Query()], session: SessionDep
) -> ReportList:
    query = report_query(filters)
    total = session.scalar(select(func.count()).select_from(query.subquery())) or 0
    rows = session.scalars(
        query.order_by(Report.created_at.desc(), Report.id.desc())
        .offset(filters.offset)
        .limit(filters.limit)
    )
    return ReportList(items=[serialize(row) for row in rows], total=total)


def find_report(report_id: UUID, session: Session) -> Report:
    report = session.get(Report, report_id)
    if report is None:
        raise HTTPException(404)
    return report


@router.get("/{report_id}", response_model=ReportOut)
def get_report(report_id: UUID, session: SessionDep) -> ReportOut:
    return serialize(find_report(report_id, session))


@router.get("/{report_id}/photo", response_class=FileResponse)
def get_photo(
    report_id: UUID, session: SessionDep, services: ServicesDep
) -> FileResponse:
    find_report(report_id, session)
    path = services.storage.path(report_id)
    if not path.is_file():
        raise HTTPException(404)
    return FileResponse(
        path, media_type="image/jpeg", headers={"X-Content-Type-Options": "nosniff"}
    )
