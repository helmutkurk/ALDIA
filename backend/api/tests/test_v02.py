from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from test_reports import fields, photo, submit

OPERATOR = {"X-Staff-Token": "o" * 32}
SUPERVISOR = {"X-Staff-Token": "s" * 32}


def enable_staff(client: TestClient) -> None:
    settings = client.app.state.services.settings
    settings.staff_token = "o" * 32
    settings.supervisor_token = "s" * 32
    settings.env = "dev"
    settings.auth_dev_tokens = True


def test_staff_flow_and_hidden_visibility(client: TestClient) -> None:
    report = submit(client).json()
    path = f"/api/reports/{report['id']}"
    assert (
        client.post(path + "/assign", json={"assignee": "Cuadrilla"}).status_code == 401
    )
    enable_staff(client)
    for headers in [{}, {"X-Staff-Token": "incorrect"}]:
        for suffix, body in [
            ("/assign", {"assignee": None}),
            ("/transition", {"to": "en_revision"}),
        ]:
            assert (
                client.post(path + suffix, headers=headers, json=body).status_code
                == 401
            )
    assigned = client.post(
        path + "/assign", headers=OPERATOR, json={"assignee": "Cuadrilla"}
    )
    assert assigned.status_code == 200
    assert assigned.json()["assignee"] == "Cuadrilla"
    assert len(client.get(path).json()["events"]) == 2
    changed = client.post(
        path + "/transition",
        headers=OPERATOR,
        json={"to": "en_revision", "internal_note": "Revisión privada"},
    )
    assert changed.status_code == 200
    assert changed.json()["events"][-1]["internal_note"] == "Revisión privada"
    assert "internal_note" not in client.get(path).json()["events"][-1]
    assert (
        client.post(
            path + "/transition", headers=OPERATOR, json={"to": "resuelto"}
        ).status_code
        == 409
    )
    assert (
        client.post(
            path + "/transition", headers=OPERATOR, json={"to": "oculto"}
        ).status_code
        == 403
    )
    assert (
        client.post(
            path + "/transition", headers=SUPERVISOR, json={"to": "oculto"}
        ).status_code
        == 200
    )
    assert (
        client.get(path).status_code
        == client.get(report["photo_url"]).status_code
        == 404
    )
    assert client.get(path, headers=OPERATOR).status_code == 200
    assert client.get("/api/reports").json()["total"] == 0
    assert client.get("/api/stats").json()["total"] == 0
    assert client.get("/api/open311/v2/requests.json").json() == []
    assert report["id"] not in client.get("/api/reports.csv").text
    restored = client.post(
        path + "/transition", headers=SUPERVISOR, json={"to": "en_revision"}
    )
    assert restored.status_code == 200
    assert restored.json()["state"] == "en_revision"


def test_idempotency_replay_and_expiry(client: TestClient) -> None:
    key = str(uuid4())

    def post():
        return client.post(
            "/api/reports",
            headers={"Idempotency-Key": key},
            data=fields(),
            files={"photo": ("x.jpg", photo())},
        )

    first = post()
    second = post()
    assert first.status_code == 201
    assert second.status_code == 200
    assert first.json() == second.json()
    assert client.get("/api/reports").json()["total"] == 1
    assert len(list(client.app.state.services.settings.photo_dir.glob("*.jpg"))) == 1
    from app.models import IdempotencyRecord

    with client.app.state.services.database.sessions() as session:
        record = session.get(IdempotencyRecord, UUID(key))
        record.created_at = datetime.now(UTC) - timedelta(hours=25)
        session.commit()
    assert post().status_code == 201
    assert client.get("/api/reports").json()["total"] == 2
    assert (
        client.post("/api/reports", headers={"Idempotency-Key": "bad"}).status_code
        == 422
    )


def test_nearby_clusters_queue(client: TestClient) -> None:
    enable_staff(client)
    first = submit(client).json()
    second = submit(client, latitude="14.6355").json()
    third = submit(client, latitude="14.6361").json()
    result = client.get(
        "/api/reports/nearby?lat=14.6349&lon=-90.5069&category=pothole&radius_m=150"
    )
    assert result.status_code == 200
    assert [r["id"] for r in result.json()["items"]] == [
        first["id"],
        second["id"],
        third["id"],
    ]
    assert result.json()["items"][0]["thumbnail_url"] == first["photo_url"]
    nearby = client.get(f"/api/reports/{first['id']}/nearby").json()
    assert [r["id"] for r in nearby["items"]] == [second["id"]]
    bbox = "-91,14,-90,15"
    low = client.get(f"/api/reports/clusters?bbox={bbox}&zoom=1").json()
    high = client.get(f"/api/reports/clusters?bbox={bbox}&zoom=17").json()
    assert low["total"] == high["total"] == 3
    assert len(low["clusters"]) == 1
    assert low["clusters"][0]["count"] == 3
    assert len(high["clusters"]) == 3
    assert all(c["count"] == 1 for c in high["clusters"])
    assert client.get("/api/queue").status_code == 401
    queue = client.get(
        "/api/queue?tab=review&limit=1&offset=1", headers=OPERATOR
    ).json()
    assert queue["total"] == 3 and queue["limit"] == 1 and queue["offset"] == 1
    assert queue["items"][0]["id"] == second["id"]
    assert queue["items"][0]["age_hours"] >= 0


@pytest.mark.parametrize(
    "url",
    [
        "/api/reports?limit=101",
        "/api/reports?state=bad",
        "/api/reports?state_group=bad",
        "/api/reports?created_from=2026-11-20&created_to=2026-11-19",
        "/api/reports?sort=bad",
        "/api/reports/nearby?lat=0&lon=0&category=pothole&radius_m=501",
        "/api/reports/clusters?zoom=1",
        "/api/reports/clusters?bbox=-91,14,-90,15&zoom=21",
        "/api/reports.csv?delimiter=tab",
    ],
)
def test_invalid_v02_queries(client: TestClient, url: str) -> None:
    assert client.get(url).status_code == 422


def test_tokens_are_validated_redacted_and_allowed_by_cors(client: TestClient) -> None:
    from pydantic import ValidationError

    from app.config import Settings

    for name in ["staff_token", "supervisor_token"]:
        with pytest.raises(ValidationError) as raised:
            Settings(**{name: "short-test-credential"})
        assert "short-test-credential" not in str(raised.value)
    config = Settings(staff_token="o" * 32, supervisor_token="s" * 32)
    assert "o" * 32 not in repr(config)
    assert "s" * 32 not in repr(config)
    assert "staff_token" not in config.model_dump()
    response = client.options(
        "/api/reports",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "X-Staff-Token, Idempotency-Key",
        },
    )
    assert response.status_code == 200


def test_idempotency_serializes_concurrent_requests(client: TestClient) -> None:
    from concurrent.futures import ThreadPoolExecutor

    key = str(uuid4())

    def post():
        return client.post(
            "/api/reports",
            headers={"Idempotency-Key": key},
            data=fields(),
            files={"photo": ("x.jpg", photo())},
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        replies = list(pool.map(lambda _: post(), range(2)))
    assert sorted(r.status_code for r in replies) == [200, 201]
    assert replies[0].json() == replies[1].json()
    assert client.get("/api/reports").json()["total"] == 1


def test_idempotency_persists_across_service_restart(client: TestClient) -> None:
    import httpx
    from test_reports import fake_verifier

    from app.main import create_app

    key = str(uuid4())
    first = client.post(
        "/api/reports",
        headers={"Idempotency-Key": key},
        data=fields(),
        files={"photo": ("x.jpg", photo())},
    )
    app = create_app(
        client.app.state.services.settings,
        verifier_transport=httpx.MockTransport(fake_verifier),
    )
    with TestClient(app) as restarted:
        # A retry need not upload the body again once its key was committed.
        replay = restarted.post("/api/reports", headers={"Idempotency-Key": key})
        assert replay.status_code == 200
        assert replay.json() == first.json()
        assert restarted.get("/api/reports").json()["total"] == 1


def test_category_sla_and_group_contract(client: TestClient) -> None:
    expected = {
        "accessibility": (720, "movilidad"),
        "sidewalk": (720, "movilidad"),
        "pothole": (240, "movilidad"),
        "graffiti": (1440, "espacio_publico"),
        "open_drain": (72, "servicios"),
        "street_light": (168, "servicios"),
    }
    for item in client.get("/api/categories").json():
        assert (item["sla_hours"], item["group"]) == expected[item["id"]]


def test_idempotency_cannot_disclose_a_hidden_case(client: TestClient) -> None:
    enable_staff(client)
    key = str(uuid4())
    headers = {"Idempotency-Key": key}
    original = client.post(
        "/api/reports",
        headers=headers,
        data=fields(),
        files={"photo": ("x.jpg", photo())},
    ).json()
    path = f"/api/reports/{original['id']}"
    assert (
        client.post(
            path + "/transition", headers=SUPERVISOR, json={"to": "oculto"}
        ).status_code
        == 200
    )
    replay = client.post("/api/reports", headers=headers)
    assert replay.status_code == 404
    assert original["id"] not in replay.text
    assert client.get("/api/reports", headers=SUPERVISOR).json()["total"] == 1
