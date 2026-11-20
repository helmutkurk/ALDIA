"""Domain-separated keyed identifiers; no raw citizen identity in persistence."""

import hashlib
import hmac
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, Request
from sqlalchemy.orm import Session

from app.config import Settings
from app.models import Citizen, CitizenSession
from app.security import constant_equal, digest
from app.serialization import utc


def keyed(settings: Settings, domain: str, value: str) -> str:
    key = settings.citizen_hash_key
    if key is None:
        raise HTTPException(503, detail="citizen_unavailable")
    return hmac.new(
        key.encode(), (domain + ":" + value).encode(), hashlib.sha256
    ).hexdigest()


def normalize_phone(value: str) -> str:
    if re.fullmatch(r"[0-9]{8}", value):
        value = "+502" + value
    if not re.fullmatch(r"\+[1-9][0-9]{7,14}", value):
        raise ValueError("Invalid phone format")
    if value.startswith("+502") and len(value) != 12:
        raise ValueError("Invalid Guatemala phone format")
    return value


@dataclass(frozen=True)
class CitizenIdentity:
    id: str
    session_id: str
    public_alias: str | None


def identity(
    request: Request, session: Session, settings: Settings
) -> CitizenIdentity | None:
    authorization = request.headers.get("Authorization")
    device_id = request.headers.get("X-Device-ID")
    if authorization is None and device_id is None:
        return None
    scheme, _, token = (authorization or "").partition(" ")
    try:
        device = str(UUID(device_id or ""))
    except ValueError:
        raise HTTPException(401, detail="citizen_unauthorized") from None
    if scheme.lower() != "bearer" or not re.fullmatch(r"[A-Za-z0-9_-]{43}", token):
        raise HTTPException(401, detail="citizen_unauthorized")
    if settings.citizen_hash_key is None:
        raise HTTPException(401, detail="citizen_unauthorized")
    record = session.get(CitizenSession, digest(token))
    if (
        record is None
        or not constant_equal(record.device_hash, keyed(settings, "device", device))
        or utc(record.expires_at) <= datetime.now(UTC)
    ):
        raise HTTPException(401, detail="citizen_unauthorized")
    citizen = session.get(Citizen, record.citizen_id)
    if citizen is None:
        raise HTTPException(401, detail="citizen_unauthorized")
    return CitizenIdentity(
        citizen.id, record.id, citizen.alias if citizen.alias_public else None
    )
