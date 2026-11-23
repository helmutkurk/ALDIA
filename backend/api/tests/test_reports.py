from collections.abc import Callable, Iterator
from datetime import UTC, datetime, timedelta
from io import BytesIO
from pathlib import Path
from uuid import UUID, uuid4

import httpx
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.db import Base
from app.main import create_app
from app.schemas import ReportCreate
from app.services.duplicates import distance_metres, hamming_distance
from app.services.storage import PhotoStorage


def photo(fmt: str = "JPEG", exif: bool = False) -> bytes:
    buffer = BytesIO()
    image = Image.new("RGB", (640, 480), "orange")
    metadata = Image.Exif()
    if exif:
        metadata[270] = "synthetic test image"
        metadata[34853] = {1: "N", 2: (14.0, 30.0, 0.0)}
    image.save(buffer, format=fmt, exif=metadata)
    return buffer.getvalue()


def fields(**overrides: str) -> dict[str, str]:
    return {
        "category": "pothole",
        "latitude": "14.6349",
        "longitude": "-90.5069",
        "captured_at": datetime.now(UTC).isoformat(),
        **overrides,
    }


def fake_verifier(request: httpx.Request) -> httpx.Response:
    if request.url.path == "/health":
        return httpx.Response(200, json={"status": "ok", "mode": "stub"})
    assert request.url.path == "/verify"
    assert b'name="photo"' in request.content
    return httpx.Response(
        200,
        json={
            "passed": True,
            "mode": "stub",
            "phash": "0000000000000000",
            "checks": [
                {
                    "name": name,
                    "passed": True,
                    "detail": "stub: not classified" if name == "category" else "ok",
                }
                for name in ["image", "place", "freshness", "category"]
            ],
        },
    )


@pytest.fixture
def client(tmp_path: Path, database_url: Callable[[str], str]) -> Iterator[TestClient]:
    settings = Settings(
        database_url=database_url("test"),
        photo_dir=tmp_path / "photos",
        cors_origins="http://localhost:5173",
    )
    app = create_app(settings, verifier_transport=httpx.MockTransport(fake_verifier))
    Base.metadata.create_all(app.state.services.database.engine)
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client


def submit(client: TestClient, **overrides: str) -> httpx.Response:
    return client.post(
        "/api/reports",
        data=fields(**overrides),
        files={"photo": ("ignored.txt", photo(), "text/plain")},
    )


def test_health_categories_and_cors(client: TestClient) -> None:
    assert client.get("/api/health").json()["status"] == "ok"
    categories = client.get("/api/categories").json()
    assert len(categories) == 6
    assert {c["id"] for c in categories} == {
        "accessibility",
        "sidewalk",
        "pothole",
        "graffiti",
        "open_drain",
        "street_light",
    }
    assert (
        client.options(
            "/api/reports",
            headers={
                "Origin": "http://localhost:5173",
                "Access-Control-Request-Method": "POST",
            },
        ).headers["access-control-allow-origin"]
        == "http://localhost:5173"
    )


def test_create_and_get(client: TestClient) -> None:
    response = submit(client, note="Bache en la acera")
    assert response.status_code == 201
    report = response.json()
    assert report["status"] == "verified"
    assert report["resolution"] == "open"
    assert report["note"] == "Bache en la acera"
    assert report["verification"]["mode"] == "stub"
    assert report["verification"]["checks"][-1]["name"] == "duplicate"
    assert report["created_at"].endswith("Z")
    assert report["captured_at"].endswith("Z")
    assert report["photo_url"] == f"/api/reports/{report['id']}/photo"
    assert client.get(f"/api/reports/{report['id']}").json() == report


@pytest.mark.parametrize(
    "overrides",
    [
        {"latitude": "91"},
        {"latitude": "-91"},
        {"longitude": "181"},
        {"longitude": "-181"},
        {"latitude": "nan"},
        {"longitude": "inf"},
        {"category": "unknown"},
        {"note": "x" * 281},
        {"captured_at": (datetime.now(UTC) + timedelta(seconds=120)).isoformat()},
        {"captured_at": "2026-11-19T18:00:00"},
        {"captured_at": "yesterday"},
        {"extra": "forbidden"},
    ],
)
def test_validation(client: TestClient, overrides: dict[str, str]) -> None:
    response = submit(client, **overrides)
    assert response.status_code == 422
    assert set(response.json()) == {"error"}
    assert set(response.json()["error"]) == {"code", "message"}
    assert client.get("/api/reports").json()["total"] == 0


def test_missing_and_repeated_fields(client: TestClient) -> None:
    assert client.post("/api/reports", data=fields()).status_code == 422
    response = client.post(
        "/api/reports",
        files=[("photo", ("one.jpg", photo())), ("photo", ("two.jpg", photo()))],
        data=fields(),
    )
    assert response.status_code == 422


@pytest.mark.parametrize("data", [b"not an image", photo(fmt="GIF"), photo()[:100]])
def test_photo_sniffing_rejects_invalid(client: TestClient, data: bytes) -> None:
    response = client.post(
        "/api/reports",
        data=fields(),
        files={"photo": ("valid.jpg", data, "image/jpeg")},
    )
    assert response.status_code == 422


@pytest.mark.parametrize("fmt", ["JPEG", "PNG"])
def test_photo_endpoint_strips_metadata(client: TestClient, fmt: str) -> None:
    response = client.post(
        "/api/reports", data=fields(), files={"photo": ("x", photo(fmt, exif=True))}
    )
    assert response.status_code == 201
    downloaded = client.get(response.json()["photo_url"])
    assert downloaded.status_code == 200
    assert downloaded.headers["content-type"] == "image/jpeg"
    with Image.open(BytesIO(downloaded.content)) as image:
        assert image.format == "JPEG"
        assert len(image.getexif()) == 0
        assert "gps" not in image.info


def test_upload_limit(client: TestClient) -> None:
    client.app.state.services.settings.max_upload_bytes = 100
    assert submit(client).status_code == 413


def test_filters_and_pagination(client: TestClient) -> None:
    first = submit(client).json()
    second = submit(
        client, category="graffiti", latitude="19.4", longitude="-99.1"
    ).json()
    rejected = submit(client).json()
    assert rejected["status"] == "rejected"
    result = client.get("/api/reports").json()
    assert result["total"] == 3
    assert [r["id"] for r in result["items"]] == [
        rejected["id"],
        second["id"],
        first["id"],
    ]
    for query in [
        "category=graffiti",
        "bbox=-100,19,-99,20",
        "status=verified&category=graffiti",
    ]:
        result = client.get(f"/api/reports?{query}").json()
        assert result["total"] == 1
        assert result["items"][0]["id"] == second["id"]
    assert client.get("/api/reports?status=rejected").json()["total"] == 1
    result = client.get("/api/reports?limit=1&offset=1").json()
    assert result["total"] == 3
    assert result["items"][0]["id"] == second["id"]


@pytest.mark.parametrize(
    "query",
    [
        "bbox=bad",
        "bbox=1,2,0,3",
        "bbox=nan,0,1,2",
        "bbox=-181,0,1,2",
        "bbox=0,-91,1,2",
        "category=unknown",
        "status=unknown",
        "resolution=unknown",
        "limit=0",
        "limit=501",
        "offset=-1",
        "extra=1",
    ],
)
def test_invalid_filters(client: TestClient, query: str) -> None:
    response = client.get(f"/api/reports?{query}")
    assert response.status_code == 422
    assert "error" in response.json()


def test_missing_reports_and_invalid_ids(client: TestClient) -> None:
    for suffix in ["", "/photo"]:
        assert client.get(f"/api/reports/{uuid4()}{suffix}").status_code == 404
        assert client.get(f"/api/reports/not-a-uuid{suffix}").status_code == 422
    assert client.get("/unknown").json()["error"]["code"] == "not_found"


def test_duplicate_same_category_and_distance(client: TestClient) -> None:
    assert submit(client).json()["status"] == "verified"
    duplicate = submit(client, latitude="14.6350").json()
    assert duplicate["status"] == "rejected"
    assert duplicate["verification"]["passed"] is False
    assert duplicate["verification"]["checks"][-1]["passed"] is False
    assert submit(client, category="graffiti").json()["status"] == "verified"
    assert submit(client, latitude="14.6360").json()["status"] == "verified"


def test_verifier_unreachable_is_pending(client: TestClient) -> None:
    def down(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("private internal URL", request=request)

    services = client.app.state.services
    services.verifier.client.close()
    services.verifier.client = httpx.Client(transport=httpx.MockTransport(down))
    response = submit(client)
    assert response.status_code == 201
    assert response.json()["status"] == "pending"
    assert response.json()["verification"] is None
    assert client.get(response.json()["photo_url"]).status_code == 200


@pytest.mark.parametrize(
    "reply", [httpx.Response(503), httpx.Response(200, json={"passed": "yes"})]
)
def test_bad_verifier_is_pending(client: TestClient, reply: httpx.Response) -> None:
    services = client.app.state.services
    services.verifier.client.close()
    services.verifier.client = httpx.Client(
        transport=httpx.MockTransport(lambda _request: reply)
    )
    assert submit(client).json()["status"] == "pending"


def test_server_errors_are_redacted(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    def fail(_data: bytes) -> bytes:
        raise RuntimeError("private database password")

    monkeypatch.setattr(client.app.state.services.storage, "prepare", fail)
    response = submit(client)
    assert response.status_code == 500
    assert response.json() == {
        "error": {"code": "internal_error", "message": "Error interno del servidor."}
    }
    assert "password" not in response.text


def test_hash_and_distance_boundaries() -> None:
    assert hamming_distance("0000000000000000", "000000000000000f") == 4
    assert hamming_distance("0000000000000000", "000000000000001f") == 5
    assert distance_metres(0, 0, 0, 0) == 0
    assert 49 < distance_metres(0, 0, 0, 0.00044966) < 51
    assert distance_metres(0, 179.9999, 0, -179.9999) < 50


def test_storage_rejects_non_uuid(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="UUID"):
        PhotoStorage(tmp_path).path("../../etc/passwd")


def test_schema_is_strict() -> None:
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        ReportCreate.model_validate({**fields(), "latitude": True, "longitude": -90.5})


def test_database_failure_removes_photo(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from sqlalchemy.orm import Session

    def fail_commit(_session: Session) -> None:
        raise RuntimeError("database failed")

    monkeypatch.setattr(Session, "commit", fail_commit)
    assert submit(client).status_code == 500
    assert list(client.app.state.services.settings.photo_dir.glob("*.jpg")) == []
    assert client.get("/api/reports").json()["total"] == 0


def test_missing_photo_on_disk(client: TestClient) -> None:
    report = submit(client).json()
    client.app.state.services.storage.path(report["id"]).unlink()
    response = client.get(report["photo_url"])
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


@pytest.mark.parametrize(
    ("phash", "status"),
    [
        ("000000000000000f", "rejected"),
        ("000000000000001f", "verified"),
    ],
)
def test_duplicate_hamming_threshold(
    client: TestClient, phash: str, status: str
) -> None:
    submit(client)

    def reply(request: httpx.Request) -> httpx.Response:
        body = fake_verifier(request).json()
        body["phash"] = phash
        return httpx.Response(200, json=body)

    services = client.app.state.services
    services.verifier.client.close()
    services.verifier.client = httpx.Client(transport=httpx.MockTransport(reply))
    assert submit(client).json()["status"] == status


def test_failed_verifier_check_rejects_report(client: TestClient) -> None:
    def reply(request: httpx.Request) -> httpx.Response:
        body = fake_verifier(request).json()
        body["passed"] = False
        body["checks"][0]["passed"] = False
        return httpx.Response(200, json=body)

    services = client.app.state.services
    services.verifier.client.close()
    services.verifier.client = httpx.Client(transport=httpx.MockTransport(reply))
    response = submit(client)
    assert response.status_code == 201
    assert response.json()["status"] == "rejected"


def test_chunked_oversize_body(client: TestClient) -> None:
    services = client.app.state.services
    services.settings.max_upload_bytes = 100

    def chunks() -> Iterator[bytes]:
        for _ in range(10):
            yield b"x" * 10000

    response = client.post(
        "/api/reports",
        content=chunks(),
        headers={"Content-Type": "multipart/form-data; boundary=test"},
    )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "upload_too_large"


def test_unsupported_origin(client: TestClient) -> None:
    response = client.get("/api/health", headers={"Origin": "https://example.invalid"})
    assert "access-control-allow-origin" not in response.headers


def test_migration_round_trip(
    monkeypatch: pytest.MonkeyPatch, database_url: Callable[[str], str]
) -> None:
    from alembic.config import Config
    from sqlalchemy import create_engine, inspect

    from alembic import command

    url = database_url("migration")
    monkeypatch.setenv("DATABASE_URL", url)
    config = Config("alembic.ini")
    command.upgrade(config, "head")
    engine = create_engine(url)
    try:
        assert "reports" in inspect(engine).get_table_names()
        command.check(config)
        command.downgrade(config, "base")
        assert "reports" not in inspect(engine).get_table_names()
    finally:
        engine.dispose()


def test_cors_errors_are_uniform(client: TestClient) -> None:
    response = client.options(
        "/api/reports",
        headers={
            "Origin": "https://not-allowed.invalid",
            "Access-Control-Request-Method": "POST",
        },
    )
    assert response.status_code == 400
    assert set(response.json()) == {"error"}


def test_method_error_preserves_allow_header(client: TestClient) -> None:
    response = client.delete("/api/health")
    assert response.status_code == 405
    assert response.headers["allow"] == "GET"
    assert set(response.json()) == {"error"}


def test_internal_error_includes_cors(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    def fail(_data: bytes) -> bytes:
        raise RuntimeError("failure")

    monkeypatch.setattr(client.app.state.services.storage, "prepare", fail)
    response = client.post(
        "/api/reports",
        data=fields(),
        files={"photo": ("x", photo())},
        headers={"Origin": "http://localhost:5173"},
    )
    assert response.status_code == 500
    assert response.headers["access-control-allow-origin"] == "http://localhost:5173"


# Synthetic rows exercise read views without involving photo/verifier behavior.
def seed_reports(client: TestClient) -> list[str]:
    from app.models import Report

    ids = []
    with client.app.state.services.database.sessions() as session:
        for index, (category, status, resolution) in enumerate(
            [
                ("pothole", "verified", "open"),
                ("graffiti", "verified", "acknowledged"),
                ("pothole", "verified", "fixed"),
                ("pothole", "rejected", "fixed"),
                ("graffiti", "pending", "open"),
            ]
        ):
            report_id = uuid4()
            ids.append(str(report_id))
            session.add(
                Report(
                    id=report_id,
                    category=category,
                    latitude=14.5 if index != 1 else 19.4,
                    longitude=-90.5 if index != 1 else -99.1,
                    captured_at=datetime(2026, 11, 10 + index, 11, tzinfo=UTC),
                    created_at=datetime(2026, 11, 10 + index, 12, tzinfo=UTC),
                    status=status,
                    resolution=resolution,
                    state=(
                        "resuelto"
                        if resolution == "fixed"
                        else "en_proceso"
                        if resolution == "acknowledged"
                        else "pendiente_verificacion"
                        if status == "pending"
                        else "nuevo"
                    ),
                    state_changed_at=datetime(2026, 11, 10 + index, 12, tzinfo=UTC),
                    verified_at=(
                        datetime(2026, 11, 10 + index, 12, tzinfo=UTC)
                        if status != "pending"
                        else None
                    ),
                    resolved_at=(
                        datetime(2026, 11, 10 + index, 12, tzinfo=UTC)
                        if resolution == "fixed"
                        else None
                    ),
                    note="Luminaria dañada, reparar\npor favor" if index == 1 else None,
                    verification=None,
                    phash=None,
                )
            )
        session.commit()
    return ids


def test_resolution_list_and_detail(client: TestClient) -> None:
    ids = seed_reports(client)
    result = client.get("/api/reports?resolution=fixed&include_old=true").json()
    assert result["total"] == 2
    assert [row["id"] for row in result["items"]] == [ids[3], ids[2]]
    assert all(row["resolution"] == "fixed" for row in result["items"])
    assert client.get(f"/api/reports/{ids[1]}").json()["resolution"] == "acknowledged"
    assert submit(client, resolution="fixed").status_code == 422


@pytest.mark.parametrize(
    "path", ["/api/stats", "/api/reports.csv", "/api/open311/v2/requests.json"]
)
def test_empty_read_views(client: TestClient, path: str) -> None:
    import csv
    from io import StringIO

    response = client.get(path)
    assert response.status_code == 200
    if path == "/api/stats":
        from app.categories import CATEGORY_IDS

        stats = response.json()
        assert stats["total"] == 0
        assert stats["by_category"] == dict.fromkeys(CATEGORY_IDS, 0)
        assert stats["by_status"] == dict.fromkeys(
            ["pending", "verified", "rejected"], 0
        )
        assert stats["by_resolution"] == dict.fromkeys(
            ["open", "acknowledged", "fixed", "closed"], 0
        )
        assert stats["recibidos"] == stats["resueltos"] == stats["abiertos"] == 0
        assert stats["resolucion_horas"] == {
            "median": None,
            "p90": None,
            "mean": None,
            "n": 0,
        }
        assert stats["tasa_resolucion"] is None
        assert stats["sla_cumplido"] is None
    elif path.endswith(".csv"):
        assert list(csv.reader(StringIO(response.content.decode("utf-8-sig")))) == [
            [
                "id",
                "created_at",
                "verified_at",
                "category",
                "state",
                "state_changed_at",
                "resolved_at",
                "latitude",
                "longitude",
                "assignee",
                "verifier_status",
                "duplicates_count",
                "days_open",
                "link",
            ]
        ]
    else:
        assert response.json() == []


def test_stats_counts(client: TestClient) -> None:
    seed_reports(client)
    response = client.get("/api/stats?include_old=true")
    assert response.status_code == 200
    stats = response.json()
    assert stats["total"] == 5
    assert stats["by_category"]["pothole"] == 3
    assert stats["by_category"]["graffiti"] == 2
    assert stats["by_category"]["street_light"] == 0
    assert stats["by_status"] == {"pending": 1, "verified": 3, "rejected": 1}
    assert stats["by_resolution"] == {
        "open": 2,
        "acknowledged": 1,
        "fixed": 2,
        "closed": 0,
    }


@pytest.mark.parametrize(
    ("query", "indexes"),
    [
        ("category=graffiti", [4, 1]),
        ("bbox=-100,19,-99,20", [1]),
        ("status=rejected", [3]),
        ("resolution=fixed", [3, 2]),
        ("bbox=-91,14,-90,15&category=pothole&status=verified&resolution=fixed", [2]),
        ("category=street_light", []),
    ],
)
def test_shared_read_filters(
    client: TestClient, query: str, indexes: list[int]
) -> None:
    import csv
    from io import StringIO

    ids = seed_reports(client)
    listed = client.get(f"/api/reports?{query}&include_old=true").json()
    stats_response = client.get(f"/api/stats?{query}&include_old=true")
    csv_response = client.get(f"/api/reports.csv?{query}&include_old=true")
    assert stats_response.status_code == csv_response.status_code == 200
    stats = stats_response.json()
    rows = list(csv.DictReader(StringIO(csv_response.content.decode("utf-8-sig"))))
    assert [row["id"] for row in rows] == [ids[index] for index in indexes]
    assert listed["total"] == stats["total"] == len(indexes)
    for key in ["by_category", "by_status", "by_resolution"]:
        assert sum(stats[key].values()) == len(indexes)
    for key, column in [("category", "category"), ("status", "verifier_status")]:
        for value, count in stats[f"by_{key}"].items():
            assert count == sum(row[column] == value for row in rows)
    for value, count in stats["by_resolution"].items():
        assert count == sum(row["resolution"] == value for row in listed["items"])


@pytest.mark.parametrize("path", ["/api/reports", "/api/stats", "/api/reports.csv"])
@pytest.mark.parametrize(
    "query",
    [
        "resolution=unknown",
        "category=bad",
        "status=open",
        "bbox=nan,0,1,2",
        "bbox=1,2,0,3",
        "bbox=bad",
    ],
)
def test_invalid_shared_read_filters(client: TestClient, path: str, query: str) -> None:
    response = client.get(f"{path}?{query}")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_csv_shape_and_injection(client: TestClient) -> None:
    import csv
    from io import StringIO

    from app.models import Report

    ids = seed_reports(client)
    response = client.get("/api/reports.csv?include_old=true")
    assert response.status_code == 200
    assert response.headers["content-type"] == "text/csv; charset=utf-8"
    assert (
        response.headers["content-disposition"]
        == "attachment; filename=aldia-reports.csv"
    )
    rows = list(csv.DictReader(StringIO(response.content.decode("utf-8-sig"))))
    assert response.content.startswith(b"\xef\xbb\xbf")
    assert len(rows) == 5
    days_open = float(rows[-1].pop("days_open"))
    assert days_open == pytest.approx(
        (datetime.now(UTC) - datetime(2026, 11, 10, 12, tzinfo=UTC)).total_seconds()
        / 86400,
        abs=1 / 86400,
    )
    assert rows[-1] == {
        "id": ids[0],
        "category": "pothole",
        "latitude": "14.5",
        "longitude": "-90.5",
        "created_at": "2026-11-10T12:00:00Z",
        "verified_at": "2026-11-10T12:00:00Z",
        "state": "nuevo",
        "state_changed_at": "2026-11-10T12:00:00Z",
        "resolved_at": "",
        "assignee": "",
        "verifier_status": "verified",
        "duplicates_count": "0",
        "link": f"/api/reports/{ids[0]}",
    }
    # Exercise all dangerous prefixes and CSV quoting, including non-ASCII text.
    for prefix in ["=", "+", "-", "@"]:
        with client.app.state.services.database.sessions() as session:
            row = session.get(Report, UUID(ids[0]))
            assert row is not None
            row.category = f'{prefix}fórmula,"dato"\nsegunda línea'
            session.commit()
        rows = list(
            csv.DictReader(
                StringIO(
                    client.get("/api/reports.csv?include_old=true").content.decode(
                        "utf-8-sig"
                    )
                )
            )
        )
        assert rows[-1]["category"] == f'\'{prefix}fórmula,"dato"\nsegunda línea'


def test_open311_shape_and_verified_only(client: TestClient) -> None:
    ids = seed_reports(client)
    response = client.get("/api/open311/v2/requests.json")
    assert response.status_code == 200
    rows = response.json()
    assert [row["service_request_id"] for row in rows] == [ids[2], ids[1], ids[0]]
    assert rows[1] == {
        "service_request_id": ids[1],
        "status": "open",
        "service_code": "graffiti",
        "service_name": "Grafiti",
        "description": "Luminaria dañada, reparar\npor favor",
        "lat": 19.4,
        "long": -99.1,
        "requested_datetime": "2026-11-11T12:00:00Z",
        "updated_datetime": "2026-11-11T12:00:00Z",
        "media_url": f"/api/reports/{ids[1]}/photo",
    }
    assert rows[0]["status"] == "closed"
    assert rows[0]["description"] == ""
    assert rows[2]["status"] == "open"


@pytest.mark.parametrize(
    ("query", "indexes"),
    [
        ("service_code=graffiti", [1]),
        ("status=open", [1, 0]),
        ("status=closed", [2]),
        ("start_date=2026-11-11T12:00:00Z", [2, 1]),
        ("end_date=2026-11-11T12:00:00Z", [1, 0]),
        (
            "start_date=2026-11-11T13:00:00%2B01:00&end_date=2026-11-11T12:00:00Z&service_code=graffiti&status=open",
            [1],
        ),
        ("service_code=street_light", []),
        ("service_code=graffiti&status=closed", []),
    ],
)
def test_open311_filters(client: TestClient, query: str, indexes: list[int]) -> None:
    ids = seed_reports(client)
    response = client.get(f"/api/open311/v2/requests.json?{query}")
    assert response.status_code == 200
    assert [row["service_request_id"] for row in response.json()] == [
        ids[index] for index in indexes
    ]


@pytest.mark.parametrize(
    "query",
    [
        "status=verified",
        "service_code=bad",
        "start_date=bad",
        "end_date=2026-11-11T12:00:00",
        "start_date=2026-11-12T12:00:00Z&end_date=2026-11-11T12:00:00Z",
    ],
)
def test_open311_invalid_filters(client: TestClient, query: str) -> None:
    response = client.get(f"/api/open311/v2/requests.json?{query}")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_export_caps(client: TestClient) -> None:
    import csv
    from io import StringIO

    from sqlalchemy import insert

    from app.models import Report

    with client.app.state.services.database.sessions() as session:
        session.execute(
            insert(Report),
            [
                dict(
                    id=uuid4(),
                    category="pothole",
                    latitude=14.5,
                    longitude=-90.5,
                    captured_at=datetime(2026, 11, 10, tzinfo=UTC),
                    created_at=datetime(2026, 11, 10, tzinfo=UTC),
                    status="verified",
                    state="nuevo",
                    state_changed_at=datetime(2026, 11, 10, tzinfo=UTC),
                    verified_at=datetime(2026, 11, 10, tzinfo=UTC),
                )
                for _ in range(5001)
            ],
        )
        session.commit()
    assert client.get("/api/stats?include_old=true").json()["total"] == 5001
    assert (
        len(
            list(
                csv.DictReader(
                    StringIO(
                        client.get("/api/reports.csv?include_old=true").content.decode(
                            "utf-8-sig"
                        )
                    )
                )
            )
        )
        == 5000
    )
    rows = client.get("/api/open311/v2/requests.json").json()
    assert len(rows) == 1000
    assert [row["service_request_id"] for row in rows] == sorted(
        [row["service_request_id"] for row in rows], reverse=True
    )


def test_resolution_migration_existing_rows(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    database_url: Callable[[str], str],
) -> None:
    from alembic.config import Config
    from sqlalchemy import create_engine, text
    from sqlalchemy.exc import IntegrityError

    from alembic import command

    url = database_url("upgrade")
    monkeypatch.setenv("DATABASE_URL", url)
    config = Config("alembic.ini")
    command.upgrade(config, "0001")
    engine = create_engine(url)
    try:
        with engine.begin() as connection:
            connection.execute(
                text(
                    "INSERT INTO reports (id, category, latitude, longitude, "
                    "captured_at, created_at, status) VALUES (:id, 'pothole', "
                    "14.5, -90.5, '2026-11-10 12:00:00', "
                    "'2026-11-10 12:00:00', 'verified')"
                ),
                {"id": uuid4().hex},
            )
        command.upgrade(config, "head")
        with engine.connect() as connection:
            assert connection.scalar(text("SELECT resolution FROM reports")) == "open"
        with engine.begin() as connection:
            connection.execute(text("UPDATE reports SET resolution = 'closed'"))
            assert connection.scalar(text("SELECT resolution FROM reports")) == "closed"
        with engine.begin() as connection, pytest.raises(IntegrityError):
            connection.execute(text("UPDATE reports SET resolution = 'unknown'"))
        command.downgrade(config, "0001")
        with engine.connect() as connection:
            assert connection.scalar(text("SELECT count(*) FROM reports")) == 1
    finally:
        engine.dispose()
