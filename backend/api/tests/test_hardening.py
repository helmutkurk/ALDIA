from collections.abc import Iterator
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy.exc import OperationalError

from app.config import Settings
from app.main import create_app
from app.middleware import PublicPostLimiter


@pytest.fixture
def hardened(tmp_path: Path) -> Iterator[TestClient]:
    settings = Settings(
        database_url="sqlite://",
        photo_dir=tmp_path / "photos",
        public_post_rate_limit=2,
        public_post_window_seconds=60,
    )
    app = create_app(
        settings,
        verifier_transport=httpx.MockTransport(
            lambda request: httpx.Response(200, json={"status": "ok"})
        ),
    )
    with TestClient(app, raise_server_exceptions=False) as client:
        yield client


def test_public_posts_share_peer_budget_and_keep_cors(hardened: TestClient) -> None:
    assert hardened.post("/api/reports").status_code == 422
    assert hardened.post("/api/auth/login", json={}).status_code == 422
    response = hardened.post(
        "/api/reports",
        headers={"X-Forwarded-For": "203.0.113.55", "Origin": "http://localhost:5173"},
    )
    assert response.status_code == 429
    assert response.json()["error"]["code"] == "rate_limited"
    assert 1 <= int(response.headers["retry-after"]) <= 60
    assert response.headers["access-control-allow-origin"] == "http://localhost:5173"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert hardened.get("/api/categories").status_code == 200


def test_rate_window_expires_and_peers_are_independent(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    now = 100.0
    monkeypatch.setattr("app.middleware.time.monotonic", lambda: now)
    limiter = PublicPostLimiter(
        Settings(public_post_rate_limit=1, public_post_window_seconds=10)
    )
    assert limiter.retry_after("one") == 0
    assert limiter.retry_after("one") == 10
    assert limiter.retry_after("two") == 0
    now = 110.0
    assert limiter.retry_after("one") == 0


@pytest.mark.parametrize(
    "method,path",
    [
        ("get", "/api/categories"),
        ("get", "/missing"),
        ("post", "/api/reports"),
        ("delete", "/api/health"),
        ("options", "/api/reports"),
        ("patch", "/api/admin/users/invalid"),
    ],
)
def test_security_headers_cover_success_and_errors(
    hardened: TestClient, method: str, path: str
) -> None:
    response = hardened.request(
        method,
        path,
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "POST",
        },
    )
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["referrer-policy"] == "no-referrer"
    assert (
        response.headers["permissions-policy"]
        == "camera=(), microphone=(), geolocation=()"
    )
    assert "server" not in response.headers and "x-powered-by" not in response.headers


def test_security_headers_on_oversized_json(hardened: TestClient) -> None:
    for method, path in (
        ("POST", "/api/auth/login"),
        ("PATCH", "/api/admin/users/invalid"),
    ):
        response = hardened.request(method, path, content=b"x" * 65537)
        assert response.status_code == 413
        assert response.json()["error"]["code"] == "upload_too_large"
        assert response.headers["x-content-type-options"] == "nosniff"


def test_security_headers_cover_unhandled_error(
    hardened: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    def broken() -> bool:
        raise RuntimeError("private diagnostic")

    monkeypatch.setattr(hardened.app.state.services.verifier, "healthy", broken)
    response = hardened.get("/api/health", headers={"Origin": "http://localhost:5173"})
    assert response.status_code == 500
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["referrer-policy"] == "no-referrer"
    assert "private diagnostic" not in response.text


@pytest.mark.parametrize(
    "origin",
    [
        "*",
        "https://*.example.org",
        "null",
        "https://example.org/path",
        "https://example.org/",
    ],
)
def test_cors_requires_explicit_origins(origin: str) -> None:
    with pytest.raises(ValidationError):
        Settings(cors_origins=origin)
    assert Settings(cors_origins="").allowed_origins == []


def test_health_probes_dependencies_and_private_photo_directory(
    hardened: TestClient,
) -> None:
    root = hardened.app.state.services.storage.root
    root.mkdir()
    root.chmod(0o777)
    response = hardened.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "dependencies": {"database": "ok", "verifier": "ok", "photos": "ok"},
    }
    assert root.stat().st_mode & 0o777 == 0o700
    assert list(root.iterdir()) == []


@pytest.mark.parametrize("dependency", ["database", "verifier", "photos"])
def test_health_reports_dependency_failure(
    hardened: TestClient, monkeypatch: pytest.MonkeyPatch, dependency: str
) -> None:
    services = hardened.app.state.services
    if dependency == "database":

        def fail() -> None:
            raise OperationalError("SELECT 1", {}, Exception("private connection data"))

        monkeypatch.setattr(services.database.engine, "connect", fail)
    elif dependency == "photos":

        def unwritable() -> None:
            raise PermissionError("private path")

        monkeypatch.setattr(services.storage, "probe", unwritable)
    else:
        monkeypatch.setattr(services.verifier, "healthy", lambda: False)
    response = hardened.get("/api/health")
    assert response.status_code == 503
    assert response.json()["status"] == "degraded"
    assert response.json()["dependencies"][dependency] == "unavailable"
    assert response.headers["cache-control"] == "no-store"
    assert "private" not in response.text


def test_health_verifier_timeout_is_sanitized(
    hardened: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    def timeout(*args: object, **kwargs: object) -> None:
        raise httpx.ReadTimeout("private verifier URL")

    monkeypatch.setattr(hardened.app.state.services.verifier.client, "get", timeout)
    response = hardened.get("/api/health")
    assert response.status_code == 503
    assert response.json()["dependencies"]["verifier"] == "unavailable"
