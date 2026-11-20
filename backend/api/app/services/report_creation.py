"""Report creation transaction, verification and idempotency ownership policy."""

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from fastapi import HTTPException
from sqlalchemy import delete, text

from app.citizen_security import CitizenIdentity
from app.dependencies import Services
from app.models import IdempotencyRecord, Report, ReportEvent
from app.report_queries import find_report
from app.schemas import Check, ReportCreate, ReportOut, Status, Verification
from app.serialization import detail
from app.services.duplicates import is_duplicate
from app.state_machine import State, resolution_for


def check_replay_owner(report: Report, citizen: CitizenIdentity | None) -> None:
    if report.citizen_id != (citizen.id if citizen else None):
        raise HTTPException(409, detail="idempotency_conflict")


def create_report(
    data: ReportCreate,
    content: bytes,
    services: Services,
    key: UUID | None,
    citizen: CitizenIdentity | None = None,
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
                existing = find_report(record.report_id, session)
                check_replay_owner(existing, citizen)
                return detail(existing, session), True
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
        if verification is None:
            status: Status = "pending"
            state: State = "pendiente_verificacion"
        elif verification.passed:
            status, state = "verified", "nuevo"
        else:
            status, state = "rejected", "rechazado_verificador"
        report = Report(
            id=uuid4(),
            citizen_id=citizen.id if citizen else None,
            citizen_alias=citizen.public_alias if citizen else None,
            category=data.category,
            latitude=data.latitude,
            longitude=data.longitude,
            captured_at=data.captured_at,
            created_at=now,
            note=data.note,
            status=status,
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
