"""Synthetic citizen integration. Never emit phones, OTPs or credentials."""

import secrets
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient
from test_reports import fake_verifier, fields, photo

from app.config import Settings
from app.db import Base
from app.main import create_app


class CapturingSms:
    def __init__(self):
        self.messages = []

    def send_code(self, phone, code):
        self.messages.append(code)


@pytest.fixture
def citizen_client(tmp_path):
    app = create_app(
        Settings(
            env="dev",
            database_url=f"sqlite:///{tmp_path / 'citizens.db'}",
            photo_dir=tmp_path / "photos",
            public_post_rate_limit=1000,
        ),
        verifier_transport=httpx.MockTransport(fake_verifier),
    )
    Base.metadata.create_all(app.state.services.database.engine)
    app.state.services.sms = CapturingSms()
    with TestClient(app, raise_server_exceptions=False) as client:
        yield client


def identity():
    return {
        "phone": "+502" + str(secrets.randbelow(10**7) + 20_000_000),
        "device_id": str(uuid4()),
    }


def request_code(client, who):
    return client.post("/api/citizens/otp/request", json=who)


def verify(client, who, **extra):
    return client.post(
        "/api/citizens/otp/verify",
        json={**who, "code": client.app.state.services.sms.messages[-1], **extra},
    )


def login(client, who=None, **extra):
    who = who or identity()
    request_code(client, who)
    result = verify(client, who, **extra)
    assert result.status_code == 200
    return {
        "Authorization": "Bearer " + result.json()["token"],
        "X-Device-ID": who["device_id"],
    }


def post_report(client, headers=None):
    return client.post(
        "/api/reports",
        headers=headers,
        data=fields(),
        files={"photo": ("synthetic.jpg", photo(), "image/jpeg")},
    )


def test_request_enumeration_resistance(citizen_client):
    who = identity()
    first = request_code(citizen_client, who)
    assert verify(citizen_client, who).status_code == 200
    known = request_code(citizen_client, who)
    repeated = request_code(citizen_client, who)
    unknown = request_code(citizen_client, identity())
    assert [r.status_code for r in (first, known, repeated, unknown)] == [202] * 4
    assert first.content == known.content == repeated.content == unknown.content
    assert all(
        r.headers["cache-control"] == "no-store"
        for r in (first, known, repeated, unknown)
    )


def test_attempt_budget_cannot_be_reset(citizen_client):
    who = identity()
    request_code(citizen_client, who)
    actual = citizen_client.app.state.services.sms.messages[-1]
    wrong = str((int(actual) + 1) % 1_000_000).zfill(6)
    for _ in range(5):
        r = citizen_client.post("/api/citizens/otp/verify", json={**who, "code": wrong})
        assert r.status_code == 401
        assert r.json()["error"]["code"] == "citizen_code_invalid"
    request_code(citizen_client, who)
    assert verify(citizen_client, who).status_code == 401


def test_expiry_and_unknown_share_error(citizen_client):
    from app.models import CitizenChallenge

    who = identity()
    request_code(citizen_client, who)
    with citizen_client.app.state.services.database.sessions() as session:
        challenge = session.query(CitizenChallenge).one()
        challenge.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        session.commit()
    expired = verify(citizen_client, who)
    unknown = citizen_client.post(
        "/api/citizens/otp/verify",
        json={**identity(), "code": str(secrets.randbelow(1_000_000)).zfill(6)},
    )
    assert expired.status_code == unknown.status_code == 401
    assert expired.content == unknown.content


def test_binding_consumption_rotation_logout(citizen_client):
    who = identity()
    old = login(citizen_client, who)
    assert verify(citizen_client, who).status_code == 401
    assert (
        citizen_client.get(
            "/api/citizens/me/reports", headers={**old, "X-Device-ID": str(uuid4())}
        ).status_code
        == 401
    )
    request_code(citizen_client, who)
    new = verify(citizen_client, who)
    assert new.status_code == 200
    expiry = datetime.fromisoformat(new.json()["expires_at"].replace("Z", "+00:00"))
    assert timedelta(days=89) < expiry - datetime.now(UTC) <= timedelta(days=90)
    current = {**old, "Authorization": "Bearer " + new.json()["token"]}
    assert (
        citizen_client.get("/api/citizens/me/reports", headers=old).status_code == 401
    )
    assert (
        citizen_client.get("/api/citizens/me/reports", headers=current).status_code
        == 200
    )
    assert (
        citizen_client.post("/api/citizens/logout", headers=current).status_code == 204
    )
    assert (
        citizen_client.get("/api/citizens/me/reports", headers=current).status_code
        == 401
    )


def test_ownership_idempotency_and_required_flag(citizen_client):
    owner = login(citizen_client)
    other = login(citizen_client)
    key = {"Idempotency-Key": str(uuid4())}
    created = post_report(citizen_client, {**owner, **key})
    assert created.status_code == 201
    assert "citizen_id" not in created.json()
    assert post_report(citizen_client, {**owner, **key}).status_code == 200
    assert post_report(citizen_client, {**other, **key}).status_code == 409
    assert post_report(citizen_client, key).status_code == 409
    mine = citizen_client.get("/api/citizens/me/reports", headers=owner).json()
    theirs = citizen_client.get("/api/citizens/me/reports", headers=other).json()
    assert mine["total"] == 1 and theirs["total"] == 0
    assert mine["items"][0]["id"] == created.json()["id"]
    assert post_report(citizen_client).status_code == 201
    citizen_client.app.state.services.settings.require_citizen_login = True
    assert post_report(citizen_client).status_code == 401
    assert post_report(citizen_client, owner).status_code == 201
    citizen_client.app.state.services.settings.require_citizen_login = False
    assert (
        post_report(citizen_client, {"Authorization": "Bearer invalid"}).status_code
        == 401
    )


def test_null_provider(citizen_client):
    from app.services.sms import NullSmsProvider

    citizen_client.app.state.services.sms = NullSmsProvider()
    who = identity()
    assert request_code(citizen_client, who).status_code == 202
    r = citizen_client.post(
        "/api/citizens/otp/verify",
        json={**who, "code": str(secrets.randbelow(1_000_000)).zfill(6)},
    )
    assert r.status_code == 401


def test_alias_opt_in(citizen_client):
    private = login(citizen_client, alias="Vecina")
    public = login(citizen_client, alias="Vecino", alias_public=True)
    assert post_report(citizen_client, private).json().get("citizen_alias") is None
    assert post_report(citizen_client, public).json()["citizen_alias"] == "Vecino"


def test_request_phone_limit_and_cooldown(citizen_client):
    from app.models import CitizenChallenge

    who = identity()
    request_code(citizen_client, who)
    sms = citizen_client.app.state.services.sms
    assert len(sms.messages) == 1
    request_code(citizen_client, who)
    assert len(sms.messages) == 1
    # Third request is outside the cooldown but within the phone's 15m budget.
    with citizen_client.app.state.services.database.sessions() as session:
        session.query(CitizenChallenge).one().sent_at = datetime.now(UTC) - timedelta(
            seconds=61
        )
        session.commit()
    request_code(citizen_client, who)
    assert len(sms.messages) == 2
    with citizen_client.app.state.services.database.sessions() as session:
        session.query(CitizenChallenge).one().sent_at = datetime.now(UTC) - timedelta(
            seconds=61
        )
        session.commit()
    assert request_code(citizen_client, who).status_code == 202
    assert len(sms.messages) == 2


def test_request_ip_limit_ignores_forwarded_ip(citizen_client):
    for _ in range(10):
        request_code(citizen_client, identity())
    r = citizen_client.post(
        "/api/citizens/otp/request",
        json=identity(),
        headers={"X-Forwarded-For": "192.0.2.1"},
    )
    assert r.status_code == 202
    assert len(citizen_client.app.state.services.sms.messages) == 10


def test_verification_limits_phone_and_ip(citizen_client):
    who = identity()
    for _ in range(10):
        r = citizen_client.post(
            "/api/citizens/otp/verify",
            json={**who, "code": str(secrets.randbelow(1_000_000)).zfill(6)},
        )
        assert r.status_code == 401
    r = citizen_client.post(
        "/api/citizens/otp/verify",
        json={**who, "code": str(secrets.randbelow(1_000_000)).zfill(6)},
    )
    assert r.status_code == 429 and int(r.headers["retry-after"]) > 0
    for _ in range(19):
        r = citizen_client.post(
            "/api/citizens/otp/verify",
            json={**identity(), "code": str(secrets.randbelow(1_000_000)).zfill(6)},
        )
        assert r.status_code == 401
    r = citizen_client.post(
        "/api/citizens/otp/verify",
        json={**identity(), "code": str(secrets.randbelow(1_000_000)).zfill(6)},
    )
    assert r.status_code == 429


def test_resend_invalidates_old_code_preserves_attempts(citizen_client):
    from app.models import CitizenChallenge

    who = identity()
    request_code(citizen_client, who)
    old_code = citizen_client.app.state.services.sms.messages[-1]
    with citizen_client.app.state.services.database.sessions() as session:
        row = session.query(CitizenChallenge).one()
        row.attempts = 3
        row.sent_at = datetime.now(UTC) - timedelta(seconds=61)
        session.commit()
    request_code(citizen_client, who)
    with citizen_client.app.state.services.database.sessions() as session:
        assert session.query(CitizenChallenge).one().attempts == 3
    assert citizen_client.app.state.services.sms.messages[-1] != old_code
    r = citizen_client.post("/api/citizens/otp/verify", json={**who, "code": old_code})
    assert r.status_code == 401
    assert verify(citizen_client, who).status_code == 200


def test_token_expiry_and_separate_devices_keep_ownership(citizen_client):
    from app.models import CitizenSession

    who = identity()
    first = login(citizen_client, who)
    assert post_report(citizen_client, first).status_code == 201
    second_who = {**who, "device_id": str(uuid4())}
    second = login(citizen_client, second_who)
    for headers in (first, second):
        r = citizen_client.get("/api/citizens/me/reports", headers=headers)
        assert r.status_code == 200 and r.json()["total"] == 1
    with citizen_client.app.state.services.database.sessions() as session:
        for row in session.query(CitizenSession):
            row.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        session.commit()
    assert (
        citizen_client.get("/api/citizens/me/reports", headers=first).status_code == 401
    )
    assert post_report(citizen_client, second).status_code == 401


def test_wrong_challenge_device_and_no_private_data(citizen_client, caplog):
    from app.models import Citizen, CitizenChallenge, CitizenSession

    who = identity()
    request_code(citizen_client, who)
    r = verify(citizen_client, {**who, "device_id": str(uuid4())})
    assert r.status_code == 401
    code = citizen_client.app.state.services.sms.messages[-1]
    result = verify(citizen_client, who)
    assert result.status_code == 200
    raw = result.json()["token"]
    with citizen_client.app.state.services.database.sessions() as session:
        owner = session.query(Citizen).one()
        token = session.query(CitizenSession).one()
        assert owner.phone_last2 == who["phone"][-2:]
        assert len(owner.id) == len(owner.phone_hash) == len(token.id) == 64
        assert who["phone"] not in (owner.id, owner.phone_hash, owner.phone_last2)
        assert raw != token.id and who["device_id"] != token.device_hash
        assert session.query(CitizenChallenge).count() == 0
    assert all(
        value not in caplog.text
        for value in (who["phone"], who["device_id"], code, raw)
    )


def test_production_fails_closed_without_key(citizen_client):
    services = citizen_client.app.state.services
    services.settings.env = "production"
    assert services.settings.citizen_hash_key is None
    r = request_code(citizen_client, identity())
    assert r.status_code == 202
    assert len(services.sms.messages) == 0
    with pytest.raises(ValueError, match="PHONE_HASH_KEY"):
        create_app(Settings(require_citizen_login=True))


def test_console_is_dev_only_and_no_phone_in_log(citizen_client, caplog):
    from app.services.sms import ConsoleSmsProvider, NullSmsProvider, SmsUnavailable

    with pytest.raises(ValueError):
        ConsoleSmsProvider(Settings(env="production"))
    with pytest.raises(SmsUnavailable):
        NullSmsProvider().send_code("unused", "unused")
    sms = ConsoleSmsProvider(citizen_client.app.state.services.settings)
    code = str(secrets.randbelow(1_000_000)).zfill(6)
    who = identity()
    sms.send_code(who["phone"], code)
    assert "DEV ONLY" in caplog.text and code in caplog.text
    assert who["phone"] not in caplog.text


@pytest.mark.parametrize(
    "field,value",
    [
        ("phone", "invalid"),
        ("device_id", "invalid"),
        ("phone", "+502"),
        ("phone", "１２３４５６７８"),
    ],
)
def test_validation_is_private(citizen_client, field, value):
    r = request_code(citizen_client, {**identity(), field: value})
    assert r.status_code == 422
    assert r.json() == {
        "error": {"code": "validation_error", "message": "Solicitud inválida."}
    }
    assert r.headers["cache-control"] == "no-store"


def test_hidden_reports_and_internal_notes_stay_private(citizen_client):
    from app.models import Report, ReportEvent

    headers = login(citizen_client)
    created = post_report(citizen_client, headers).json()
    with citizen_client.app.state.services.database.sessions() as session:
        session.query(ReportEvent).first().internal_note = "internal only"
        session.commit()
    r = citizen_client.get("/api/citizens/me/reports", headers=headers)
    assert "internal only" not in r.text and "citizen_id" not in r.text
    with citizen_client.app.state.services.database.sessions() as session:
        session.query(Report).one().state = "oculto"
        session.commit()
    assert (
        citizen_client.get("/api/citizens/me/reports", headers=headers).json()["total"]
        == 0
    )
    assert (
        citizen_client.get("/api/reports/" + created["id"], headers=headers).status_code
        == 404
    )


def test_cors_allows_citizen_headers(citizen_client):
    r = citizen_client.options(
        "/api/citizens/me/reports",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "Authorization,X-Device-ID",
        },
    )
    assert r.status_code == 200


def test_bare_guatemala_phone_has_same_identity(citizen_client):
    who = identity()
    request_code(citizen_client, who)
    assert verify(citizen_client, {**who, "phone": who["phone"][4:]}).status_code == 200


def test_limiter_window_recovers_and_bounds_keys(citizen_client, monkeypatch):
    from app.middleware import PublicPostLimiter

    clock = [1_000.0]
    monkeypatch.setattr("app.middleware.time.monotonic", lambda: clock[0])
    limiter = PublicPostLimiter(
        citizen_client.app.state.services.settings, limit=1, window=900
    )
    assert limiter.retry_after("synthetic") == 0
    assert limiter.retry_after("synthetic") == 900
    clock[0] += 900
    assert limiter.retry_after("synthetic") == 0
    # Cap distinct live keys with fail-closed suppression rather than eviction.
    from collections import deque

    limiter.buckets = {str(i): deque([clock[0]]) for i in range(10_000)}
    assert limiter.retry_after("new-key") == 900
    assert len(limiter.buckets) == 10_000


def test_populated_citizen_migration_round_trip(tmp_path, monkeypatch):
    from alembic.config import Config
    from sqlalchemy import create_engine, inspect, text

    from alembic import command

    url = f"sqlite:///{tmp_path / 'migration.db'}"
    monkeypatch.setenv("DATABASE_URL", url)
    config = Config("alembic.ini")
    command.upgrade(config, "0004")
    engine = create_engine(url)
    try:
        with engine.begin() as connection:
            connection.execute(
                text(
                    "INSERT INTO reports (id,category,latitude,longitude,"
                    "captured_at,created_at,status,resolution,state,state_changed_at) "
                    "VALUES (:id,'pothole',14.5,-90.5,'2026-11-20 12:00:00',"
                    "'2026-11-20 12:00:00','pending','open',"
                    "'pendiente_verificacion','2026-11-20 12:00:00')"
                ),
                {"id": uuid4().hex},
            )
        command.upgrade(config, "head")
        with engine.begin() as connection:
            assert connection.scalar(text("SELECT citizen_id FROM reports")) is None
            connection.execute(
                text(
                    "INSERT INTO citizens (id,phone_hash,phone_last2,alias_public) "
                    "VALUES (:id,:phone,:tail,0)"
                ),
                {
                    "id": secrets.token_hex(32),
                    "phone": secrets.token_hex(32),
                    "tail": str(secrets.randbelow(100)).zfill(2),
                },
            )
            connection.execute(
                text(
                    "UPDATE reports SET citizen_id=(SELECT id FROM citizens), "
                    "citizen_alias='Vecina'"
                )
            )
        command.check(config)
        command.downgrade(config, "0004")
        assert "citizens" not in inspect(engine).get_table_names()
        assert "citizen_id" not in {
            column["name"] for column in inspect(engine).get_columns("reports")
        }
        with engine.connect() as connection:
            assert connection.scalar(text("SELECT count(*) FROM reports")) == 1
        command.upgrade(config, "head")
        command.check(config)
    finally:
        engine.dispose()


def test_citizen_errors_preserve_unrelated_staff_cookie(citizen_client):
    from app.security import SESSION_COOKIE

    citizen_client.cookies.set(SESSION_COOKIE, "synthetic-unrelated-cookie")
    r = citizen_client.post(
        "/api/citizens/otp/verify",
        json={**identity(), "code": str(secrets.randbelow(1_000_000)).zfill(6)},
    )
    assert r.status_code == 401
    assert "set-cookie" not in r.headers
    r = post_report(citizen_client, {"Authorization": "Bearer invalid"})
    assert r.status_code == 401
    assert "set-cookie" not in r.headers
