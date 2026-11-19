import hmac
from collections.abc import Iterator
from dataclasses import dataclass, field
from threading import Lock
from typing import Annotated, Literal, cast

from fastapi import Depends, Header, HTTPException, Request
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import Database
from app.services.storage import PhotoStorage
from app.services.verifier_client import VerifierClient


@dataclass
class Services:
    settings: Settings
    database: Database
    storage: PhotoStorage
    verifier: VerifierClient
    creation_lock: Lock = field(default_factory=Lock)


def get_services(request: Request) -> Services:
    return cast(Services, request.app.state.services)


ServicesDep = Annotated[Services, Depends(get_services)]


def get_session(services: ServicesDep) -> Iterator[Session]:
    with services.database.sessions() as session:
        yield session


SessionDep = Annotated[Session, Depends(get_session)]


StaffRole = Literal["operator", "supervisor"]


def optional_staff(
    services: ServicesDep,
    x_staff_token: Annotated[str | None, Header()] = None,
) -> StaffRole | None:
    if x_staff_token is None:
        return None
    settings = services.settings
    if not settings.staff_token:
        raise HTTPException(503)
    supplied = x_staff_token.encode("utf-8")
    # Evaluate both comparisons, even when one matches. Never log credentials.
    operator = hmac.compare_digest(supplied, settings.staff_token.encode("utf-8"))
    supervisor = hmac.compare_digest(
        supplied, (settings.supervisor_token or "").encode("utf-8")
    ) and bool(settings.supervisor_token)
    if supervisor:
        return "supervisor"
    if operator:
        return "operator"
    raise HTTPException(401)


OptionalStaffDep = Annotated[StaffRole | None, Depends(optional_staff)]


def require_staff(services: ServicesDep, role: OptionalStaffDep) -> StaffRole:
    if not services.settings.staff_token:
        raise HTTPException(503)
    if role is None:
        raise HTTPException(401)
    return role


StaffDep = Annotated[StaffRole, Depends(require_staff)]
