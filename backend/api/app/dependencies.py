import logging
from collections.abc import Iterator
from dataclasses import dataclass, field
from datetime import UTC, datetime
from threading import Lock
from typing import Annotated, cast

from fastapi import Depends, Header, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import Database
from app.middleware import PublicPostLimiter
from app.models import StaffSession, StaffUser
from app.security import (
    CSRF_COOKIE,
    SESSION_COOKIE,
    LoginLimiter,
    StaffRole,
    constant_equal,
    digest,
    signature,
)
from app.services.sms import SmsProvider, sms_provider
from app.services.storage import PhotoStorage
from app.services.verifier_client import VerifierClient


@dataclass
class Services:
    settings: Settings
    database: Database
    storage: PhotoStorage
    verifier: VerifierClient
    creation_lock: Lock = field(default_factory=Lock)
    auth_lock: Lock = field(default_factory=Lock)
    login_limiter: LoginLimiter = field(default_factory=LoginLimiter)
    sms: SmsProvider = field(init=False)
    citizen_request_phone: PublicPostLimiter = field(init=False)
    citizen_request_ip: PublicPostLimiter = field(init=False)
    citizen_verify_phone: PublicPostLimiter = field(init=False)
    citizen_verify_ip: PublicPostLimiter = field(init=False)
    citizen_lock: Lock = field(default_factory=Lock)

    def __post_init__(self) -> None:
        self.sms = sms_provider(self.settings)
        self.citizen_request_phone = PublicPostLimiter(
            self.settings, limit=3, window=900
        )
        self.citizen_request_ip = PublicPostLimiter(self.settings, limit=10, window=900)
        self.citizen_verify_phone = PublicPostLimiter(
            self.settings, limit=10, window=900
        )
        self.citizen_verify_ip = PublicPostLimiter(self.settings, limit=30, window=900)


def get_services(request: Request) -> Services:
    return cast(Services, request.app.state.services)


ServicesDep = Annotated[Services, Depends(get_services)]


def get_session(services: ServicesDep) -> Iterator[Session]:
    with services.database.sessions() as session:
        yield session


SessionDep = Annotated[Session, Depends(get_session)]


def session_record(request: Request, session: Session) -> StaffSession:
    cookie = request.cookies.get(SESSION_COOKIE, "")
    raw_id, _, supplied_signature = cookie.partition(".")
    if len(raw_id) != 43 or len(supplied_signature) != 64:
        raise HTTPException(401)
    record = session.get(StaffSession, digest(raw_id))
    if record is None or not constant_equal(
        supplied_signature, signature(raw_id, record.signing_key)
    ):
        raise HTTPException(401)
    expiry = (
        record.expires_at.replace(tzinfo=UTC)
        if record.expires_at.tzinfo is None
        else record.expires_at
    )
    if expiry <= datetime.now(UTC):
        raise HTTPException(401)
    return record


def session_identity(request: Request, session: Session) -> StaffUser:
    record = session_record(request, session)
    user = session.scalar(
        select(StaffUser).where(StaffUser.id == record.user_id).with_for_update()
    )
    if user is None or user.disabled:
        raise HTTPException(401)
    # A reset may have revoked this session while we waited on the user row lock.
    if (
        session.scalar(select(StaffSession.id).where(StaffSession.id == record.id))
        is None
    ):
        raise HTTPException(401)
    if request.method not in {"GET", "HEAD", "OPTIONS"}:
        csrf = request.cookies.get(CSRF_COOKIE, "")
        header = request.headers.get("X-CSRF-Token", "")
        if (
            not csrf
            or not constant_equal(csrf, header)
            or not constant_equal(digest(csrf), record.csrf_hash)
        ):
            raise HTTPException(403)
    request.state.staff_username = user.username
    request.state.staff_session_id = record.id
    return user


def optional_staff(
    request: Request,
    services: ServicesDep,
    session: SessionDep,
    x_staff_token: Annotated[str | None, Header()] = None,
) -> StaffRole | None:
    if SESSION_COOKIE in request.cookies:
        return cast(StaffRole, session_identity(request, session).role)
    if x_staff_token is None:
        return None
    settings = services.settings
    if not settings.dev_tokens_enabled:
        raise HTTPException(401)
    logging.getLogger(__name__).warning(
        "Development staff-token authentication attempted"
    )
    # Evaluate both comparisons, even when one matches. Never log credentials.
    operator = constant_equal(x_staff_token, settings.staff_token or "") and bool(
        settings.staff_token
    )
    supervisor = constant_equal(
        x_staff_token, settings.supervisor_token or ""
    ) and bool(settings.supervisor_token)
    if supervisor:
        request.state.staff_username = "dev:supervisor"
        return "supervisor"
    if operator:
        request.state.staff_username = "dev:operator"
        return "operator"
    raise HTTPException(401)


OptionalStaffDep = Annotated[StaffRole | None, Depends(optional_staff)]


def require_staff(role: OptionalStaffDep) -> StaffRole:
    if role is None:
        raise HTTPException(401)
    return role


StaffDep = Annotated[StaffRole, Depends(require_staff)]
