"""Staff login, revocable sessions and admin user management."""

import secrets
from contextlib import suppress
from datetime import UTC, datetime, timedelta
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import Field, SecretStr
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError

from app.dependencies import (
    ServicesDep,
    SessionDep,
    StaffDep,
    session_identity,
    session_record,
)
from app.models import AuthEvent, StaffSession, StaffUser
from app.schemas import StrictModel
from app.security import (
    CSRF_COOKIE,
    PASSWORD_HASHER,
    SESSION_COOKIE,
    SESSION_SECONDS,
    USERNAME_PATTERN,
    digest,
    hash_password,
    signature,
    verify_password,
)
from app.serialization import utc

router = APIRouter(prefix="/api")
Role = Literal["operator", "supervisor", "admin"]
Username = Annotated[str, Field(pattern=f"^{USERNAME_PATTERN}$")]


class LoginIn(StrictModel):
    username: Annotated[str, Field(min_length=1, max_length=64)]
    password: Annotated[SecretStr, Field(min_length=1, max_length=1024)]


class CreateUserIn(StrictModel):
    username: Username
    password: Annotated[SecretStr, Field(min_length=12, max_length=1024)]
    role: Role


class UpdateUserIn(StrictModel):
    disabled: bool | None = None
    password: Annotated[SecretStr | None, Field(min_length=12, max_length=1024)] = None
    role: Role | None = None


def user_out(user: StaffUser) -> dict[str, object]:
    return {
        "id": str(user.id),
        "username": user.username,
        "role": user.role,
        "disabled": user.disabled,
    }


def no_store(response: Response) -> None:
    response.headers["Cache-Control"] = "no-store"


def check_login_origin(request: Request, services: ServicesDep) -> None:
    origin = request.headers.get("origin")
    same_origin = f"{request.url.scheme}://{request.url.netloc}"
    if origin is not None and origin not in {
        same_origin,
        *services.settings.allowed_origins,
    }:
        raise HTTPException(403)


def require_admin(role: StaffDep) -> None:
    if role != "admin":
        raise HTTPException(403)


AdminDep = Annotated[None, Depends(require_admin)]


@router.get("/auth/config")
def config(services: ServicesDep, response: Response) -> dict[str, bool]:
    no_store(response)
    return {"enabled": True, "dev_tokens": services.settings.dev_tokens_enabled}


@router.post("/auth/login")
def login(
    data: LoginIn,
    request: Request,
    response: Response,
    services: ServicesDep,
    session: SessionDep,
) -> dict[str, object]:
    no_store(response)
    check_login_origin(request, services)
    username = data.username.lower()
    ip = request.client.host if request.client else "unknown"
    if not services.login_limiter.allow(username, ip):
        raise HTTPException(429, headers={"Retry-After": "900"})
    # SQLite has no row locks; serialize local logins to preserve failure counts.
    # PostgreSQL additionally locks the user row across replicas.
    with services.auth_lock:
        user = session.scalar(
            select(StaffUser).where(StaffUser.username == username).with_for_update()
        )
        now = datetime.now(UTC)
        password = data.password.get_secret_value()
        valid = verify_password(user.password_hash if user else None, password)
        actor = user.username if user else "anonymous"
        actor_role = user.role if user else "anonymous"
        locked = bool(user and user.locked_until and utc(user.locked_until) > now)
        if user and user.locked_until and not locked:
            user.failed_attempts = 0
            user.locked_until = None
        if user is None or user.disabled or locked or not valid:
            if user and not locked and not user.disabled:
                user.failed_attempts += 1
                if user.failed_attempts >= 5:
                    user.locked_until = now + timedelta(minutes=15)
                    locked = True
            session.add(
                AuthEvent(
                    actor=actor,
                    actor_role=actor_role,
                    action="login_failed",
                    target=user.username if user else None,
                )
            )
            session.commit()
            raise HTTPException(423 if locked else 401)
        user.failed_attempts = 0
        user.locked_until = None
        if PASSWORD_HASHER.check_needs_rehash(user.password_hash):
            user.password_hash = hash_password(password)
        # Only a signed presented session may be revoked during rotation.
        if SESSION_COOKIE in request.cookies:
            with suppress(HTTPException):
                session.delete(session_record(request, session))
        session.execute(delete(StaffSession).where(StaffSession.expires_at <= now))
        raw_id, csrf, signing_key = (
            secrets.token_urlsafe(32),
            secrets.token_urlsafe(32),
            secrets.token_hex(32),
        )
        session.add(
            StaffSession(
                id=digest(raw_id),
                user_id=user.id,
                signing_key=signing_key,
                csrf_hash=digest(csrf),
                expires_at=now + timedelta(seconds=SESSION_SECONDS),
            )
        )
        session.add(
            AuthEvent(
                actor=user.username,
                actor_role=user.role,
                action="login",
                target=user.username,
            )
        )
        session.commit()
        for name, value in (
            (SESSION_COOKIE, raw_id + "." + signature(raw_id, signing_key)),
            (CSRF_COOKIE, csrf),
        ):
            response.set_cookie(
                name,
                value,
                httponly=name == SESSION_COOKIE,
                secure=services.settings.env != "dev",
                samesite="lax",
                path="/",
                max_age=SESSION_SECONDS,
            )
        return {"user": {"username": user.username, "role": user.role}}


@router.get("/auth/me")
def me(request: Request, response: Response, session: SessionDep) -> dict[str, object]:
    no_store(response)
    user = session_identity(request, session)
    return {"user": {"username": user.username, "role": user.role}}


@router.post("/auth/logout", status_code=204)
def logout(
    request: Request, response: Response, services: ServicesDep, session: SessionDep
) -> None:
    user = session_identity(request, session)
    record = session.get(StaffSession, request.state.staff_session_id)
    if record:
        session.delete(record)
    session.add(
        AuthEvent(
            actor=user.username,
            actor_role=user.role,
            action="logout",
            target=user.username,
        )
    )
    session.commit()
    no_store(response)
    for name in (SESSION_COOKIE, CSRF_COOKIE):
        response.delete_cookie(
            name,
            secure=services.settings.env != "dev",
            httponly=name == SESSION_COOKIE,
            samesite="lax",
            path="/",
        )


@router.get("/admin/users")
def list_users(
    response: Response, session: SessionDep, admin: AdminDep
) -> dict[str, object]:
    no_store(response)
    return {
        "items": [
            user_out(user)
            for user in session.scalars(select(StaffUser).order_by(StaffUser.username))
        ]
    }


@router.post("/admin/users", status_code=201)
def create_user(
    data: CreateUserIn,
    request: Request,
    response: Response,
    session: SessionDep,
    admin: AdminDep,
) -> dict[str, object]:
    no_store(response)
    if session.scalar(select(StaffUser.id).where(StaffUser.username == data.username)):
        raise HTTPException(409)
    user = StaffUser(
        username=data.username,
        password_hash=hash_password(data.password.get_secret_value()),
        role=data.role,
    )
    session.add(user)
    session.add(
        AuthEvent(
            actor=request.state.staff_username,
            actor_role="admin",
            action="user_created",
            target=user.username,
        )
    )
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409) from exc
    return user_out(user)


@router.patch("/admin/users/{user_id}")
def update_user(
    user_id: UUID,
    data: UpdateUserIn,
    request: Request,
    response: Response,
    session: SessionDep,
    admin: AdminDep,
) -> dict[str, object]:
    no_store(response)
    if not data.model_fields_set or any(
        getattr(data, name) is None for name in data.model_fields_set
    ):
        raise HTTPException(422)
    user = session.scalar(
        select(StaffUser).where(StaffUser.id == user_id).with_for_update()
    )
    if user is None:
        raise HTTPException(404)
    if data.disabled is not None:
        user.disabled = data.disabled
    if data.role is not None:
        user.role = data.role
    if data.password is not None:
        user.password_hash = hash_password(data.password.get_secret_value())
        user.failed_attempts = 0
        user.locked_until = None
    session.execute(delete(StaffSession).where(StaffSession.user_id == user.id))
    session.add(
        AuthEvent(
            actor=request.state.staff_username,
            actor_role="admin",
            action="user_updated",
            target=user.username,
        )
    )
    session.commit()
    return user_out(user)
