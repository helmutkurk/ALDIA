"""Creation service keeps report, verification, events and retries consistent."""

from collections.abc import Iterator
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import httpx
import pytest
from fastapi import HTTPException
from test_reports import fake_verifier, photo

from app.citizen_security import CitizenIdentity
from app.config import Settings
from app.db import Base
from app.dependencies import Services
from app.main import create_app
from app.schemas import ReportCreate
from app.services.report_creation import create_report


@pytest.fixture
def services(tmp_path: Path) -> Iterator[Services]:
    app = create_app(
        Settings(database_url="sqlite://", photo_dir=tmp_path / "photos"),
        verifier_transport=httpx.MockTransport(fake_verifier),
    )
    services = app.state.services
    Base.metadata.create_all(services.database.engine)
    try:
        yield services
    finally:
        services.verifier.close()
        services.database.engine.dispose()


def report_data() -> ReportCreate:
    return ReportCreate(
        category="pothole",
        latitude=14.6349,
        longitude=-90.5069,
        captured_at=datetime.now(UTC),
    )


@pytest.mark.parametrize(
    "passed,status,state,resolution",
    [
        (None, "pending", "pendiente_verificacion", "open"),
        (True, "verified", "nuevo", "open"),
        (False, "rejected", "rechazado_verificador", "closed"),
    ],
)
def test_initial_outcome_and_events_agree(
    services: Services,
    monkeypatch: pytest.MonkeyPatch,
    passed: bool | None,
    status: str,
    state: str,
    resolution: str,
) -> None:
    def verify(request: httpx.Request) -> httpx.Response:
        if passed is None:
            return httpx.Response(503)
        body = fake_verifier(request).json()
        body["passed"] = passed
        body["checks"][0]["passed"] = passed
        return httpx.Response(200, json=body)

    with httpx.Client(transport=httpx.MockTransport(verify)) as client:
        monkeypatch.setattr(services.verifier, "client", client)
        report, repeated = create_report(report_data(), photo(), services, None)
    assert not repeated
    assert (report.status, report.state, report.resolution) == (
        status,
        state,
        resolution,
    )
    assert [event.to_state for event in report.events] == (
        ["pendiente_verificacion"]
        if passed is None
        else ["pendiente_verificacion", state]
    )
    assert report.state_changed_at == report.events[-1].at
    assert (report.verified_at is None) == (passed is None)
    assert (report.closed_at is not None) == (passed is False)
    assert (report.verification is None) == (passed is None)
    if report.verification is not None:
        assert report.verification.passed == passed
        assert report.verification.checks[-1].name == "duplicate"
    assert services.storage.path(report.id).is_file()


def test_creation_retry_checks_owner_before_reprocessing(services: Services) -> None:
    key = uuid4()
    data = report_data()
    original, repeated = create_report(data, photo(), services, key)
    assert not repeated
    # Invalid image bytes demonstrate the replay never processes a second upload.
    replay, repeated = create_report(data, b"invalid retry image", services, key)
    assert repeated and replay == original
    with pytest.raises(HTTPException) as error:
        create_report(
            data,
            b"invalid retry image",
            services,
            key,
            CitizenIdentity("other-owner", "other-session", None),
        )
    assert error.value.status_code == 409
    assert error.value.detail == "idempotency_conflict"
    assert set(services.storage.root.iterdir()) == {services.storage.path(original.id)}


def test_duplicate_outcome_retains_verifier_status_and_history(
    services: Services,
) -> None:
    data = report_data()
    create_report(data, photo(), services, None)
    duplicate, repeated = create_report(data, photo(), services, None)
    assert not repeated
    assert (duplicate.status, duplicate.state) == ("rejected", "rechazado_verificador")
    assert duplicate.verification is not None
    assert not duplicate.verification.passed
    assert not duplicate.verification.checks[-1].passed
    assert duplicate.events[-1].to_state == duplicate.state
    assert duplicate.closed_at == duplicate.events[-1].at
