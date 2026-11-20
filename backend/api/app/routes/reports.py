from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Header, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse
from pydantic import ValidationError
from sqlalchemy import delete, text
from starlette.concurrency import run_in_threadpool
from starlette.datastructures import UploadFile

from app.dependencies import (
    OptionalStaffDep,
    Services,
    ServicesDep,
    SessionDep,
    StaffDep,
)
from app.models import IdempotencyRecord, Report, ReportEvent
from app.report_queries import find_report, ordered_query, page, report_query
from app.schemas import (
    AssignmentIn,
    Check,
    ReportCreate,
    ReportFilters,
    ReportList,
    ReportOut,
    TransitionIn,
    Verification,
)
from app.serialization import detail, serialize, utc
from app.services.duplicates import is_duplicate
from app.state_machine import (
    InvalidTransition,
    RoleForbidden,
    resolution_for,
    validate_transition,
)

router = APIRouter(prefix="/api/reports")


def create_report(
    data: ReportCreate, content: bytes, services: Services, key: UUID | None
) -> tuple[ReportOut, bool]:
    # SQLite tests/local use one service lock; Postgres also locks across workers.
    with services.creation_lock, services.database.sessions() as session:
        if session.bind is not None and session.bind.dialect.name == "postgresql":
            session.execute(text("SELECT pg_advisory_xact_lock(219773001)"))
        now = datetime.now(UTC)
        session.execute(
            delete(IdempotencyRecord).where(
                IdempotencyRecord.created_at <= now - timedelta(hours=24)
            )
        )
        if key is not None:
            record = session.get(IdempotencyRecord, key)
            if record is not None:
                return detail(find_report(record.report_id, session), session), True
        try:
            clean = services.storage.prepare(content)
        except ValueError as exc:
            raise HTTPException(422) from exc
        result = services.verifier.verify(clean, data)
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
        answered_at = datetime.now(UTC)
        state = (
            "pendiente_verificacion"
            if verification is None
            else "nuevo"
            if verification.passed
            else "rechazado_verificador"
        )
        report = Report(
            id=uuid4(),
            category=data.category,
            latitude=data.latitude,
            longitude=data.longitude,
            captured_at=data.captured_at,
            created_at=now,
            note=data.note,
            status="pending"
            if verification is None
            else "verified"
            if verification.passed
            else "rejected",
            state=state,
            resolution=resolution_for(state),
            state_changed_at=answered_at if verification else now,
            verified_at=answered_at if verification else None,
            closed_at=answered_at if state == "rechazado_verificador" else None,
            phash=None if result is None else result.phash,
            verification=None if verification is None else verification.model_dump(),
        )
        session.add(report)
        session.flush()
        session.add(
            ReportEvent(
                report_id=report.id,
                actor_role="system",
                from_state=None,
                to_state="pendiente_verificacion",
                at=now,
            )
        )
        if verification is not None:
            session.add(
                ReportEvent(
                    report_id=report.id,
                    actor_role="system",
                    from_state="pendiente_verificacion",
                    to_state=state,
                    at=answered_at,
                )
            )
        if key is not None:
            session.add(IdempotencyRecord(key=key, report_id=report.id, created_at=now))
        services.storage.save(report.id, clean)
        try:
            session.commit()
        except Exception:
            services.storage.delete(report.id)
            raise
        return detail(report, session), False


@router.post(
    "", status_code=201, response_model=ReportOut, response_model_exclude_unset=True
)
async def post_report(
    request: Request,
    response: Response,
    services: ServicesDep,
    idempotency_key: Annotated[UUID | None, Header()] = None,
) -> ReportOut:
    if idempotency_key is not None:
        with services.database.sessions() as session:
            record = session.get(IdempotencyRecord, idempotency_key)
            if record is not None and datetime.now(UTC) - utc(
                record.created_at
            ) < timedelta(hours=24):
                response.status_code = 200
                return detail(find_report(record.report_id, session), session)
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
        report, repeated = await run_in_threadpool(
            create_report, data, content, services, idempotency_key
        )
        if repeated:
            response.status_code = 200
        return report


@router.get("", response_model=ReportList, response_model_exclude_unset=True)
def list_reports(
    filters: Annotated[ReportFilters, Query()],
    session: SessionDep,
    role: OptionalStaffDep,
) -> ReportList:
    rows, total = page(
        session,
        ordered_query(
            report_query(filters, include_hidden=role is not None), filters.sort
        ),
        filters.limit,
        filters.offset,
    )
    return ReportList(
        items=[serialize(row) for row in rows],
        total=total,
        limit=filters.limit,
        offset=filters.offset,
    )


@router.get("/{report_id}", response_model=ReportOut, response_model_exclude_unset=True)
def get_report(
    report_id: UUID, session: SessionDep, role: OptionalStaffDep
) -> ReportOut:
    return detail(
        find_report(report_id, session, staff=role is not None),
        session,
        staff=role is not None,
    )


@router.get("/{report_id}/photo", response_class=FileResponse)
def get_photo(
    report_id: UUID, session: SessionDep, services: ServicesDep, role: OptionalStaffDep
) -> FileResponse:
    find_report(report_id, session, staff=role is not None)
    path = services.storage.path(report_id)
    if not path.is_file():
        raise HTTPException(404)
    return FileResponse(
        path, media_type="image/jpeg", headers={"X-Content-Type-Options": "nosniff"}
    )


@router.post(
    "/{report_id}/transition",
    response_model=ReportOut,
    response_model_exclude_unset=True,
)
def transition_report(
    report_id: UUID,
    data: TransitionIn,
    request: Request,
    session: SessionDep,
    role: StaffDep,
) -> ReportOut:
    report = find_report(report_id, session, staff=True, lock=True)
    try:
        validate_transition(
            report.state,
            data.to,
            role,
            data.public_note,
            data.internal_note,
            report.previous_state,
        )
    except RoleForbidden as exc:
        raise HTTPException(403) from exc
    except InvalidTransition as exc:
        raise HTTPException(409) from exc
    if data.to == "duplicado" and report.state != "oculto":
        if data.duplicate_of is None or data.duplicate_of == report_id:
            raise HTTPException(409)
        master = find_report(data.duplicate_of, session, staff=True)
        # Flatten chains and reject cycles, including malformed legacy chains.
        visited = {report_id}
        while master.duplicate_of is not None:
            if master.id in visited:
                raise HTTPException(409)
            visited.add(master.id)
            master = find_report(master.duplicate_of, session, staff=True)
        if master.id in visited or master.state == "oculto":
            raise HTTPException(409)
        report.duplicate_of = master.id
    elif data.duplicate_of is not None:
        raise HTTPException(409)
    previous = report.state
    now = datetime.now(UTC)
    if data.to == "oculto":
        report.previous_state = previous
    elif previous == "oculto":
        report.previous_state = None
    else:
        report.resolved_at = now if data.to == "resuelto" else None
        report.closed_at = (
            now
            if data.to in {"no_procede", "fuera_de_competencia", "duplicado"}
            else None
        )
        if previous == "duplicado":
            report.duplicate_of = None
    report.state = data.to
    report.resolution = resolution_for(data.to)
    report.state_changed_at = now
    if data.public_note is not None and data.public_note.strip():
        report.public_note = data.public_note
    session.add(
        ReportEvent(
            report_id=report.id,
            actor_role=role,
            actor=request.state.staff_username,
            from_state=previous,
            to_state=data.to,
            public_note=data.public_note,
            internal_note=data.internal_note,
            at=now,
        )
    )
    session.commit()
    return detail(report, session, staff=True)


@router.post(
    "/{report_id}/assign", response_model=ReportOut, response_model_exclude_unset=True
)
def assign_report(
    report_id: UUID, data: AssignmentIn, session: SessionDep, role: StaffDep
) -> ReportOut:
    report = find_report(report_id, session, staff=True, lock=True)
    report.assignee = data.assignee
    report.assigned_at = datetime.now(UTC)
    session.commit()
    return detail(report, session, staff=True)
