from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Header, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool
from starlette.datastructures import UploadFile

from app.citizen_security import identity
from app.dependencies import (
    OptionalStaffDep,
    ServicesDep,
    SessionDep,
    StaffDep,
)
from app.models import IdempotencyRecord, ReportEvent
from app.report_queries import find_report, ordered_query, page, report_query
from app.schemas import (
    AssignmentIn,
    ReportCreate,
    ReportFilters,
    ReportList,
    ReportOut,
    TransitionIn,
)
from app.serialization import detail, serialize, utc
from app.services.report_creation import check_replay_owner, create_report
from app.state_machine import (
    InvalidTransition,
    RoleForbidden,
    resolution_for,
    validate_transition,
)

router = APIRouter(prefix="/api/reports")


@router.post(
    "", status_code=201, response_model=ReportOut, response_model_exclude_unset=True
)
async def post_report(
    request: Request,
    response: Response,
    services: ServicesDep,
    idempotency_key: Annotated[UUID | None, Header()] = None,
) -> ReportOut:
    with services.database.sessions() as auth_session:
        citizen = identity(request, auth_session, services.settings)
    if services.settings.require_citizen_login and citizen is None:
        raise HTTPException(401, detail="citizen_unauthorized")
    if citizen is not None:
        response.headers["Cache-Control"] = "no-store"
    if idempotency_key is not None:
        with services.database.sessions() as session:
            record = session.get(IdempotencyRecord, idempotency_key)
            if record is not None and datetime.now(UTC) - utc(
                record.created_at
            ) < timedelta(hours=24):
                response.status_code = 200
                existing = find_report(record.report_id, session)
                check_replay_owner(existing, citizen)
                return detail(existing, session)
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
            create_report, data, content, services, idempotency_key, citizen
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


@router.get("/{report_id}/thumbnail", response_class=FileResponse)
def get_thumbnail(
    report_id: UUID, session: SessionDep, services: ServicesDep, role: OptionalStaffDep
) -> FileResponse:
    find_report(report_id, session, staff=role is not None)
    path = services.storage.thumbnail(report_id)
    if path is None:
        raise HTTPException(404)
    return FileResponse(
        path,
        media_type="image/jpeg",
        headers={
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "public, max-age=86400",
        },
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
