"""Account security integration tests use synthetic credentials exclusively."""

from datetime import UTC, datetime, timedelta
from io import StringIO
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from test_reports import submit

from app.models import AuthEvent, StaffSession, StaffUser
from app.security import PASSWORD_HASHER, digest, hash_password

PASSWORD = "synthetic staff password"


def account(
    client: TestClient, role: str = "operator", username: str = "operador"
) -> UUID:
    client.app.state.services.settings.env = "dev"
    with client.app.state.services.database.sessions() as session:
        user = StaffUser(
            username=username, role=role, password_hash=hash_password(PASSWORD)
        )
        session.add(user)
        session.commit()
        return user.id


def login(client: TestClient, username: str = "operador", password: str = PASSWORD):
    return client.post(
        "/api/auth/login", json={"username": username, "password": password}
    )


def csrf(client: TestClient) -> dict[str, str]:
    return {"X-CSRF-Token": client.cookies["aldia_csrf"]}


@pytest.mark.parametrize(
    "env,secure", [("dev", False), ("production", True), ("test", True)]
)
def test_cookie_flags_hash_parameters_and_session_store(
    client: TestClient, env: str, secure: bool
) -> None:
    account(client)
    client.app.state.services.settings.env = env
    reply = login(client)
    assert reply.status_code == 200
    assert reply.json() == {"user": {"username": "operador", "role": "operator"}}
    assert reply.headers["cache-control"] == "no-store"
    cookies = reply.headers.get_list("set-cookie")
    session_cookie = next(c for c in cookies if c.startswith("aldia_session="))
    csrf_cookie = next(c for c in cookies if c.startswith("aldia_csrf="))
    assert "HttpOnly" in session_cookie and "HttpOnly" not in csrf_cookie
    assert ("Secure" in session_cookie) is secure
    assert ("Secure" in csrf_cookie) is secure
    assert all(
        "SameSite=lax" in c and "Max-Age=43200" in c and "Path=/" in c for c in cookies
    )
    with client.app.state.services.database.sessions() as session:
        user = session.scalar(select(StaffUser))
        assert user.password_hash.startswith("$argon2id$v=19$m=65536,t=3,p=4$")
        assert PASSWORD_HASHER.verify(user.password_hash, PASSWORD)
        record = session.scalar(select(StaffSession))
        raw_id = client.cookies["aldia_session"].partition(".")[0]
        assert record.id == digest(raw_id) and record.id != raw_id
        assert record.csrf_hash == digest(client.cookies["aldia_csrf"])
        assert (
            43190
            < (
                record.expires_at.replace(tzinfo=UTC) - datetime.now(UTC)
            ).total_seconds()
            <= 43200
        )


def test_csrf_rotation_logout_and_actor(client: TestClient) -> None:
    account(client)
    report_id = submit(client).json()["id"]
    path = f"/api/reports/{report_id}"
    assert login(client).status_code == 200
    old_cookie = client.cookies["aldia_session"]
    old_csrf = client.cookies["aldia_csrf"]
    assert client.get("/api/auth/me").json()["user"]["username"] == "operador"
    for headers in ({}, {"X-CSRF-Token": "wrong"}):
        assert (
            client.post(
                path + "/assign", json={"assignee": None}, headers=headers
            ).status_code
            == 403
        )
        assert client.post("/api/auth/logout", headers=headers).status_code == 403
    # A forged matching double-submit pair cannot replace the server-bound token.
    client.cookies.set("aldia_csrf", "forged", domain="testserver.local", path="/")
    assert (
        client.post(
            path + "/assign",
            json={"assignee": None},
            headers={"X-CSRF-Token": "forged"},
        ).status_code
        == 403
    )
    assert login(client).status_code == 200
    assert client.cookies["aldia_session"] != old_cookie
    assert client.cookies["aldia_csrf"] != old_csrf
    changed = client.post(
        path + "/transition", json={"to": "en_revision"}, headers=csrf(client)
    )
    assert changed.status_code == 200
    assert changed.json()["events"][-1]["actor"] == "operador"
    assert changed.json()["events"][-1]["actor_role"] == "operator"
    assert (
        client.post(
            path + "/assign", json={"assignee": "Cuadrilla"}, headers=csrf(client)
        ).status_code
        == 200
    )
    assert client.post("/api/auth/logout", headers=csrf(client)).status_code == 204
    assert "aldia_session" not in client.cookies and "aldia_csrf" not in client.cookies
    client.cookies.set("aldia_session", old_cookie)
    assert client.get("/api/auth/me").status_code == 401
    with client.app.state.services.database.sessions() as session:
        assert session.scalar(select(func.count()).select_from(StaffSession)) == 0
        events = list(session.scalars(select(AuthEvent)))
        assert [e.action for e in events] == ["login", "login", "logout"]
        assert all(e.actor == "operador" and e.actor_role == "operator" for e in events)


def test_lockout_is_persistent_and_expires(client: TestClient) -> None:
    user_id = account(client)
    for expected in (401, 401, 401, 401, 423):
        assert login(client, password="incorrect").status_code == expected
    assert login(client).status_code == 423
    with client.app.state.services.database.sessions() as session:
        user = session.get(StaffUser, user_id)
        assert user.failed_attempts == 5
        assert (
            890
            < (
                user.locked_until.replace(tzinfo=UTC) - datetime.now(UTC)
            ).total_seconds()
            <= 900
        )
        user.locked_until = datetime.now(UTC) - timedelta(seconds=1)
        session.commit()
    assert login(client).status_code == 200
    with client.app.state.services.database.sessions() as session:
        user = session.get(StaffUser, user_id)
        assert user.failed_attempts == 0 and user.locked_until is None


def test_login_limiter_and_unknown_disabled_errors(client: TestClient) -> None:
    user_id = account(client)
    with client.app.state.services.database.sessions() as session:
        user = session.get(StaffUser, user_id)
        user.disabled = True
        session.commit()
    disabled = login(client)
    unknown = login(client, username="absent")
    assert disabled.status_code == unknown.status_code == 401
    assert disabled.json() == unknown.json()
    for _ in range(9):
        assert login(client, username="absent").status_code == 401
    limited = login(client, username="ABSENT")
    assert limited.status_code == 429 and limited.headers["retry-after"] == "900"
    assert login(client, username="different").status_code == 401


@pytest.mark.parametrize("role", ["operator", "supervisor", "admin"])
def test_role_limits_and_admin_management(client: TestClient, role: str) -> None:
    account(client, role)
    report_id = submit(client).json()["id"]
    assert login(client).status_code == 200
    payload = {"username": "new_user", "password": PASSWORD, "role": "supervisor"}
    if role != "admin":
        assert client.get("/api/admin/users").status_code == 403
        assert (
            client.post(
                "/api/admin/users", json=payload, headers=csrf(client)
            ).status_code
            == 403
        )
        assert (
            client.patch(
                f"/api/admin/users/{uuid4()}",
                json={"disabled": True},
                headers=csrf(client),
            ).status_code
            == 403
        )
    else:
        assert client.post("/api/admin/users", json=payload).status_code == 403
        created = client.post("/api/admin/users", json=payload, headers=csrf(client))
        assert created.status_code == 201
        assert set(created.json()) == {"id", "username", "role", "disabled"}
        assert (
            client.post(
                "/api/admin/users", json=payload, headers=csrf(client)
            ).status_code
            == 409
        )
        assert len(client.get("/api/admin/users").json()["items"]) == 2
        target = created.json()["id"]
        assert (
            client.patch(
                f"/api/admin/users/{target}",
                json={
                    "disabled": True,
                    "password": "new synthetic password",
                    "role": "operator",
                },
                headers=csrf(client),
            ).status_code
            == 200
        )
        for body in (
            {},
            {"password": "short"},
            {"role": "invalid"},
            {"disabled": None},
        ):
            assert (
                client.patch(
                    f"/api/admin/users/{target}", json=body, headers=csrf(client)
                ).status_code
                == 422
            )
        assert (
            client.patch(
                f"/api/admin/users/{uuid4()}",
                json={"disabled": True},
                headers=csrf(client),
            ).status_code
            == 404
        )
    hidden = client.post(
        f"/api/reports/{report_id}/transition",
        json={"to": "oculto"},
        headers=csrf(client),
    )
    assert hidden.status_code == (403 if role == "operator" else 200)
    if role == "admin":
        assert hidden.json()["events"][-1]["actor_role"] == "admin"


@pytest.mark.parametrize(
    "patch",
    [
        {"disabled": True},
        {"role": "operator"},
        {"password": "reset synthetic password"},
    ],
)
def test_admin_change_revokes_all_target_sessions(
    client: TestClient, patch: dict[str, object]
) -> None:
    target_id = account(client, "supervisor", "target")
    account(client, "admin", "admin")
    assert login(client, username="target").status_code == 200
    target_cookie = client.cookies["aldia_session"]
    client.cookies.clear()
    assert login(client, username="admin").status_code == 200
    assert (
        client.patch(
            f"/api/admin/users/{target_id}", json=patch, headers=csrf(client)
        ).status_code
        == 200
    )
    client.cookies.clear()
    client.cookies.set("aldia_session", target_cookie)
    assert client.get("/api/auth/me").status_code == 401
    with client.app.state.services.database.sessions() as session:
        assert (
            session.scalar(
                select(func.count())
                .select_from(StaffSession)
                .where(StaffSession.user_id == target_id)
            )
            == 0
        )
        event = session.scalar(
            select(AuthEvent).where(AuthEvent.action == "user_updated")
        )
        assert event.actor == "admin" and event.target == "target"


def test_tampered_expired_session_and_cors(client: TestClient) -> None:
    account(client)
    login(client)
    cookie = client.cookies["aldia_session"]
    client.cookies.clear()
    client.cookies.set(
        "aldia_session", cookie[:-1] + ("a" if cookie[-1] != "a" else "b")
    )
    assert client.get("/api/auth/me").status_code == 401
    client.cookies.clear()
    client.cookies.set("aldia_session", cookie)
    with client.app.state.services.database.sessions() as session:
        record = session.scalar(select(StaffSession))
        record.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        session.commit()
    assert client.get("/api/queue").status_code == 401
    reply = client.options(
        "/api/admin/users/anything",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "PATCH",
            "Access-Control-Request-Headers": "X-CSRF-Token, Content-Type",
        },
    )
    assert reply.status_code == 200
    assert reply.headers["access-control-allow-credentials"] == "true"
    assert reply.headers["access-control-allow-origin"] == "http://localhost:5173"


def test_dev_fallback_requires_both_flags_and_warns(
    client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    settings = client.app.state.services.settings
    settings.staff_token = "o" * 32
    settings.auth_dev_tokens = True
    assert client.get("/api/auth/config").json()["dev_tokens"] is False
    assert (
        client.get("/api/queue", headers={"X-Staff-Token": "o" * 32}).status_code == 401
    )
    settings.env = "dev"
    assert client.get("/api/auth/config").json()["dev_tokens"] is True
    assert (
        client.get("/api/queue", headers={"X-Staff-Token": "o" * 32}).status_code == 200
    )
    assert "Development staff-token" in caplog.text
    assert "o" * 32 not in caplog.text
    assert (
        client.get("/api/admin/users", headers={"X-Staff-Token": "o" * 32}).status_code
        == 403
    )


def test_cli_stdin_password_validation_and_no_secret_output(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    from app.cli import main

    monkeypatch.setenv("DATABASE_URL", client.app.state.services.settings.database_url)
    monkeypatch.setattr("sys.stdin", StringIO("short\n"))
    assert main(["create-admin"]) == 2
    monkeypatch.setattr("sys.stdin", StringIO(PASSWORD + "\n"))
    assert main(["create-admin"]) == 0
    monkeypatch.setattr("sys.stdin", StringIO(PASSWORD + "\n"))
    assert main(["create-admin"]) == 2
    captured = capsys.readouterr()
    assert PASSWORD not in captured.out + captured.err
    with client.app.state.services.database.sessions() as session:
        admin = session.scalar(select(StaffUser).where(StaffUser.username == "admin"))
        assert admin.role == "admin" and PASSWORD_HASHER.verify(
            admin.password_hash, PASSWORD
        )
