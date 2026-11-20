"""Citizen OTP exchange and private ownership reads; separate from staff auth."""

import secrets
from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Query, Request, Response
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import delete, select, text

from app.citizen_security import identity, keyed, normalize_phone
from app.dependencies import ServicesDep, SessionDep
from app.models import Citizen, CitizenChallenge, CitizenSession, Report
from app.report_queries import page
from app.schemas import ReportList
from app.security import constant_equal, digest
from app.serialization import serialize, utc
from app.services.sms import SmsUnavailable

router = APIRouter(prefix="/api/citizens", tags=["Ciudadanía"])


class OtpRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)
    phone: str = Field(min_length=8, max_length=16, repr=False)
    device_id: UUID = Field(repr=False)

    _phone = field_validator("phone")(normalize_phone)


class OtpVerify(OtpRequest):
    code: str = Field(pattern=r"^[0-9]{6}$", repr=False)
    alias: str | None = Field(default=None, min_length=1, max_length=60)
    alias_public: bool = Field(default=False, strict=True)

    @field_validator("alias")
    @classmethod
    def display_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError("Invalid alias")
        return value


class CitizenToken(BaseModel):
    token: str = Field(repr=False)
    expires_at: datetime


def peer(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def lock_database(session: SessionDep) -> None:
    # SQLite is serialized by Services.citizen_lock; PostgreSQL covers replicas.
    if session.bind is not None and session.bind.dialect.name == "postgresql":
        session.execute(text("SELECT pg_advisory_xact_lock(219773002)"))


@router.post("/otp/request", status_code=202)
def request_otp(
    data: OtpRequest,
    request: Request,
    response: Response,
    services: ServicesDep,
    session: SessionDep,
) -> dict[str, bool]:
    """Acepta la solicitud sin revelar cuentas, límites ni disponibilidad de envío."""
    response.headers["Cache-Control"] = "no-store"
    # All well-formed requests have the same response even without configuration.
    if services.settings.citizen_hash_key is None:
        return {"accepted": True}
    phone_hash = keyed(services.settings, "phone", data.phone)
    phone_retry = services.citizen_request_phone.retry_after(phone_hash)
    ip_retry = services.citizen_request_ip.retry_after(peer(request))
    if phone_retry or ip_retry:
        return {"accepted": True}
    with services.citizen_lock:
        lock_database(session)
        now = datetime.now(UTC)
        session.execute(
            delete(CitizenChallenge).where(CitizenChallenge.expires_at <= now)
        )
        challenge = session.get(CitizenChallenge, phone_hash)
        if challenge is not None and (
            utc(challenge.sent_at) + timedelta(seconds=60) > now
            or challenge.attempts >= 5
        ):
            return {"accepted": True}
        code = str(secrets.randbelow(1_000_000)).zfill(6)
        # A resend must not accidentally reissue the same six-digit value.
        while challenge is not None and constant_equal(
            challenge.code_hash,
            keyed(services.settings, "otp", challenge.nonce + ":" + code),
        ):
            code = str(secrets.randbelow(1_000_000)).zfill(6)
        nonce = uuid4().hex
        try:
            services.sms.send_code(data.phone, code)
        except SmsUnavailable:
            # No valid code exists without explicit development delivery.
            return {"accepted": True}
        if challenge is None:
            challenge = CitizenChallenge(phone_hash=phone_hash, attempts=0)
            session.add(challenge)
        challenge.phone_last2 = data.phone[-2:]
        challenge.device_hash = keyed(services.settings, "device", str(data.device_id))
        challenge.nonce = nonce
        challenge.code_hash = keyed(services.settings, "otp", nonce + ":" + code)
        challenge.sent_at = now
        challenge.expires_at = now + timedelta(minutes=10)
        session.commit()
    return {"accepted": True}


@router.post("/otp/verify", response_model=CitizenToken)
def verify_otp(
    data: OtpVerify,
    request: Request,
    response: Response,
    services: ServicesDep,
    session: SessionDep,
) -> CitizenToken:
    """Verifica un código de desarrollo y rota la sesión de este dispositivo."""
    response.headers["Cache-Control"] = "no-store"
    phone_hash = keyed(services.settings, "phone", data.phone)
    phone_retry = services.citizen_verify_phone.retry_after(phone_hash)
    ip_retry = services.citizen_verify_ip.retry_after(peer(request))
    if phone_retry or ip_retry:
        raise HTTPException(
            429, headers={"Retry-After": str(max(phone_retry, ip_retry))}
        )
    with services.citizen_lock:
        lock_database(session)
        now = datetime.now(UTC)
        device_hash = keyed(services.settings, "device", str(data.device_id))
        challenge = session.get(CitizenChallenge, phone_hash)
        # Always calculate and compare the keyed code, including unknown phones.
        expected = challenge.code_hash if challenge else "0" * 64
        supplied = keyed(
            services.settings,
            "otp",
            (challenge.nonce if challenge else "0" * 32) + ":" + data.code,
        )
        matches = constant_equal(expected, supplied)
        device_matches = constant_equal(
            challenge.device_hash if challenge else "0" * 64, device_hash
        )
        if (
            challenge is None
            or utc(challenge.expires_at) <= now
            or challenge.attempts >= 5
            or not matches
            or not device_matches
        ):
            if (
                challenge is not None
                and utc(challenge.expires_at) > now
                and challenge.attempts < 5
            ):
                challenge.attempts += 1
                session.commit()
            raise HTTPException(401, detail="citizen_code_invalid")
        citizen = session.scalar(
            select(Citizen).where(Citizen.phone_hash == phone_hash)
        )
        if citizen is None:
            citizen = Citizen(
                id=keyed(services.settings, "citizen", uuid4().hex),
                phone_hash=phone_hash,
                phone_last2=challenge.phone_last2,
            )
            session.add(citizen)
        if "alias" in data.model_fields_set:
            citizen.alias = data.alias
        # Explicit consent is required at each profile update/login.
        citizen.alias_public = data.alias_public and citizen.alias is not None
        session.flush()
        session.execute(
            delete(CitizenSession).where(
                (CitizenSession.expires_at <= now)
                | (
                    (CitizenSession.citizen_id == citizen.id)
                    & (CitizenSession.device_hash == device_hash)
                )
            )
        )
        raw_token = secrets.token_urlsafe(32)
        expiry = now + timedelta(days=90)
        session.add(
            CitizenSession(
                id=digest(raw_token),
                citizen_id=citizen.id,
                device_hash=device_hash,
                expires_at=expiry,
            )
        )
        session.delete(challenge)
        session.commit()
    return CitizenToken(token=raw_token, expires_at=expiry)


@router.post("/logout", status_code=204)
def logout(
    request: Request, response: Response, services: ServicesDep, session: SessionDep
) -> None:
    """Revoca la sesión ciudadana del dispositivo actual."""
    response.headers["Cache-Control"] = "no-store"
    owner = identity(request, session, services.settings)
    if owner is None:
        raise HTTPException(401, detail="citizen_unauthorized")
    session.execute(delete(CitizenSession).where(CitizenSession.id == owner.session_id))
    session.commit()


@router.get("/me/reports", response_model=ReportList, response_model_exclude_unset=True)
def my_reports(
    request: Request,
    response: Response,
    services: ServicesDep,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> ReportList:
    """Lista reportes de esta persona sin identificadores privados ni notas internas."""
    response.headers["Cache-Control"] = "no-store"
    owner = identity(request, session, services.settings)
    if owner is None:
        raise HTTPException(401, detail="citizen_unauthorized")
    rows, total = page(
        session,
        select(Report)
        .where(Report.citizen_id == owner.id, Report.state != "oculto")
        .order_by(Report.created_at.desc(), Report.id.desc()),
        limit,
        offset,
    )
    return ReportList(
        items=[serialize(row) for row in rows], total=total, limit=limit, offset=offset
    )
