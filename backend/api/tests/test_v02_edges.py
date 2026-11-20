from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from test_reports import submit
from test_v02 import OPERATOR, SUPERVISOR, enable_staff

from app.models import Report
from app.state_machine import resolution_for


def seed(
    client: TestClient,
    *,
    lat: float = 14.5,
    lon: float = -90.5,
    state: str = "nuevo",
    status: str = "verified",
    category: str = "pothole",
    age_days: float = 1,
    assignee: str | None = None,
    duplicate_of: str | None = None,
) -> str:
    created = datetime.now(UTC) - timedelta(days=age_days)
    report_id = uuid4()
    with client.app.state.services.database.sessions() as session:
        session.add(
            Report(
                id=report_id,
                latitude=lat,
                longitude=lon,
                category=category,
                captured_at=created,
                created_at=created,
                verified_at=created if status != "pending" else None,
                state_changed_at=created,
                state=state,
                status=status,
                resolution=resolution_for(state),
                assignee=assignee,
                duplicate_of=UUID(duplicate_of) if duplicate_of else None,
            )
        )
        session.commit()
    return str(report_id)


@pytest.mark.parametrize(
    "url",
    [
        "/api/reports/nearby?lat=91&lon=0&category=pothole",
        "/api/reports/nearby?lat=0&lon=-181&category=pothole",
        "/api/reports/nearby?lat=nan&lon=0&category=pothole",
        "/api/reports/nearby?lat=0&lon=inf&category=pothole",
        "/api/reports/nearby?lat=0&lon=0&category=unknown",
        "/api/reports/nearby?lat=0&lon=0&category=pothole&radius_m=19",
        "/api/reports/nearby?lat=0&lon=0&category=pothole&radius_m=nan",
        "/api/reports/clusters?bbox=-91,14,-90,15&zoom=-1",
        "/api/reports/clusters?bbox=-91,14,-90,15&zoom=1.5",
        "/api/reports/clusters?bbox=nan,14,-90,15&zoom=1",
        "/api/reports?include_old=maybe",
        "/api/reports?offset=-1",
        "/api/reports?limit=0",
        "/api/reports?created_from=2026-02-30",
    ],
)
def test_invalid_edge_queries(client: TestClient, url: str) -> None:
    assert client.get(url).status_code == 422


def test_staff_body_validation_and_unknown_report(client: TestClient) -> None:
    enable_staff(client)
    path = f"/api/reports/{submit(client).json()['id']}"
    for suffix, body in (
        ("/assign", {"assignee": "x" * 61}),
        ("/assign", {}),
        ("/assign", {"assignee": 123}),
        ("/transition", {"to": "bad"}),
        ("/transition", {"to": "en_revision", "public_note": "x" * 281}),
        ("/transition", {"to": "en_revision", "internal_note": "x" * 501}),
        ("/transition", {"to": "en_revision", "duplicate_of": "bad"}),
    ):
        response = client.post(path + suffix, headers=OPERATOR, json=body)
        assert response.status_code == 422, body
    unknown = f"/api/reports/{uuid4()}"
    assert client.get(unknown + "/nearby").status_code == 404
    assert (
        client.post(
            unknown + "/assign", headers=OPERATOR, json={"assignee": None}
        ).status_code
        == 404
    )
    assert (
        client.post(
            unknown + "/transition", headers=OPERATOR, json={"to": "en_revision"}
        ).status_code
        == 404
    )


def test_supervisor_override_and_reopen_requirements(client: TestClient) -> None:
    enable_staff(client)
    report_id = seed(client, state="rechazado_verificador", status="rejected")
    path = f"/api/reports/{report_id}"

    def change(body: dict[str, str], supervisor: bool = True):
        return client.post(
            path + "/transition",
            headers=SUPERVISOR if supervisor else OPERATOR,
            json=body,
        )

    assert (
        change({"to": "nuevo", "internal_note": "Override"}, False).status_code == 403
    )
    assert change({"to": "nuevo", "public_note": "Public only"}).status_code == 409
    assert change({"to": "nuevo", "internal_note": "  "}).status_code == 409
    overridden = change({"to": "nuevo", "internal_note": "Override"})
    assert overridden.status_code == 200
    assert overridden.json()["status"] == "rejected"
    assert overridden.json()["resolution"] == "open"
    assert change({"to": "en_revision"}, False).status_code == 200
    assert change({"to": "no_procede"}, False).status_code == 409
    closed = change({"to": "no_procede", "public_note": "No aplica"}, False)
    assert closed.status_code == 200
    assert closed.json()["closed_at"] is not None
    assert closed.json()["public_note"] == "No aplica"
    assert (
        change({"to": "en_revision", "internal_note": "Reopen"}, False).status_code
        == 403
    )
    assert change({"to": "en_revision"}).status_code == 409
    reopened = change({"to": "en_revision", "internal_note": "Reopen"})
    assert reopened.status_code == 200
    assert reopened.json()["closed_at"] is None
    assert reopened.json()["public_note"] == "No aplica"
    public = client.get(path)
    assert all("internal_note" not in event for event in public.json()["events"])
    assert client.get(path, headers={"X-Staff-Token": "bad"}).status_code == 401


def test_duplicate_chain_flatten_undo_cycle_and_hidden_restore(
    client: TestClient,
) -> None:
    enable_staff(client)
    master = seed(client)
    intermediary = seed(client, state="duplicado", duplicate_of=master)
    report_id = seed(client, state="en_revision")
    path = f"/api/reports/{report_id}/transition"
    for target in (None, report_id):
        body = {"to": "duplicado"}
        if target is not None:
            body["duplicate_of"] = target
        assert client.post(path, headers=OPERATOR, json=body).status_code == 409
    duplicate = client.post(
        path,
        headers=OPERATOR,
        json={"to": "duplicado", "duplicate_of": intermediary},
    )
    assert duplicate.status_code == 200
    assert duplicate.json()["duplicate_of"] == master
    assert (
        client.post(path, headers=SUPERVISOR, json={"to": "oculto"}).status_code == 200
    )
    restored = client.post(path, headers=SUPERVISOR, json={"to": "duplicado"})
    assert restored.status_code == 200
    assert restored.json()["duplicate_of"] == master
    reopened = client.post(
        path,
        headers=SUPERVISOR,
        json={"to": "en_revision", "public_note": "Caso distinto"},
    )
    assert reopened.status_code == 200
    assert reopened.json()["duplicate_of"] is None
    cycle = seed(client, state="duplicado", duplicate_of=report_id)
    assert (
        client.post(
            path,
            headers=OPERATOR,
            json={"to": "duplicado", "duplicate_of": cycle},
        ).status_code
        == 409
    )


def test_hidden_excluded_from_suggestions_and_clusters(client: TestClient) -> None:
    visible = seed(client)
    hidden = seed(client, state="oculto")
    nearby = client.get(
        "/api/reports/nearby?lat=14.5&lon=-90.5&category=pothole"
    ).json()
    assert [item["id"] for item in nearby["items"]] == [visible]
    assert client.get(f"/api/reports/{hidden}/nearby").status_code == 404
    clusters = client.get("/api/reports/clusters?bbox=-91,14,-90,15&zoom=17").json()
    assert clusters["total"] == 1
    assert clusters["clusters"][0]["ids"] == [visible]


def test_nearby_window_verified_open_and_nearest_ten(client: TestClient) -> None:
    wanted = [seed(client, lat=14.5 + i / 100000) for i in range(12)]
    seed(client, age_days=31)
    seed(client, category="graffiti")
    seed(client, state="resuelto")
    seed(client, state="nuevo", status="rejected")
    seed(client, state="pendiente_verificacion", status="pending")
    seed(client, lat=14.51)
    response = client.get(
        "/api/reports/nearby?lat=14.5&lon=-90.5&category=pothole&radius_m=500"
    )
    assert response.status_code == 200
    items = response.json()["items"]
    assert [item["id"] for item in items] == wanted[:10]
    assert [item["distance_m"] for item in items] == sorted(
        item["distance_m"] for item in items
    )
    assert all(
        item["thumbnail_url"] == item["photo_url"].replace("/photo", "/thumbnail")
        for item in items
    )


@pytest.mark.parametrize(
    ("lat", "lon", "near_lat", "near_lon"),
    [(0, 179.9995, 0, -179.9995), (90, 0, 90, 179), (-90, 0, -90, -179)],
)
def test_nearby_antimeridian_and_poles(
    client: TestClient, lat: float, lon: float, near_lat: float, near_lon: float
) -> None:
    report_id = seed(client, lat=near_lat, lon=near_lon)
    response = client.get(
        f"/api/reports/nearby?lat={lat}&lon={lon}&category=pothole&radius_m=150"
    )
    assert response.status_code == 200
    assert [item["id"] for item in response.json()["items"]] == [report_id]


def test_clusters_bbox_edges_and_cap(client: TestClient) -> None:
    first = seed(client, lat=14, lon=-91)
    last = seed(client, lat=15, lon=-90)
    seed(client, lat=15.00001, lon=-90)
    result = client.get("/api/reports/clusters?bbox=-91,14,-90,15&zoom=17").json()
    assert result["total"] == 2
    assert {report for cluster in result["clusters"] for report in cluster["ids"]} == {
        first,
        last,
    }
    for index in range(501):
        seed(client, lat=14.5, lon=-90.5 + index / 100000)
    high = client.get("/api/reports/clusters?bbox=-91,14,-90,15&zoom=20").json()
    low = client.get("/api/reports/clusters?bbox=-91,14,-90,15&zoom=0").json()
    assert high["total"] == low["total"] == 503
    assert len(high["clusters"]) == 500
    assert all(cluster["count"] == 1 for cluster in high["clusters"])
    assert sum(cluster["count"] for cluster in low["clusters"]) == 503
    assert all(len(cluster["ids"]) <= 5 for cluster in low["clusters"])
    assert all(
        set(cluster) == {"lat", "lon", "count", "ids"} for cluster in low["clusters"]
    )


def test_queue_rejected_assignment_and_filtering(client: TestClient) -> None:
    enable_staff(client)
    older = seed(client, age_days=3)
    newer = seed(client, age_days=1)
    assigned = seed(client, age_days=4, assignee="Cuadrilla")
    rejected = seed(client, state="rechazado_verificador", status="rejected")
    seed(client, state="en_revision")
    result = client.get("/api/queue?tab=review", headers=OPERATOR).json()
    assert [item["id"] for item in result["items"]] == [older, newer]
    assert result["items"][0]["age_hours"] > result["items"][1]["age_hours"]
    result = client.get("/api/queue?tab=rejected", headers=OPERATOR).json()
    assert [item["id"] for item in result["items"]] == [rejected]
    assert client.get("/api/queue?tab=bad", headers=OPERATOR).status_code == 422
    assert client.get("/api/queue", headers={"X-Staff-Token": "bad"}).status_code == 401
    assert (
        client.post(
            f"/api/reports/{assigned}/assign", headers=OPERATOR, json={"assignee": None}
        ).status_code
        == 200
    )
    result = client.get(
        "/api/queue?tab=review&category=graffiti", headers=OPERATOR
    ).json()
    assert result["items"] == []
    result = client.get("/api/queue?tab=review", headers=OPERATOR).json()
    assert result["total"] == 3


def test_window_and_state_filters_match_stats_export(client: TestClient) -> None:
    recent = seed(client, age_days=2, assignee="Cuadrilla", state="programado")
    seed(client, age_days=100, assignee="Cuadrilla", state="programado")
    seed(client, age_days=2)
    filters = "state_group=in_work&assignee=Cuadrilla"
    result = client.get(f"/api/reports?{filters}").json()
    assert [item["id"] for item in result["items"]] == [recent]
    assert result["total"] == client.get(f"/api/stats?{filters}").json()["total"] == 1
    csv = client.get(f"/api/reports.csv?{filters}").text
    assert recent in csv
    assert len(csv.splitlines()) == 2
    result = client.get(f"/api/reports?{filters}&include_old=true").json()
    assert result["total"] == 2
