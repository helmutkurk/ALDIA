"""Text search on GET /api/reports (q) and pin fields on one-report clusters."""

import re
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from test_v02 import OPERATOR, enable_staff

from alembic import command
from app.models import Report
from app.state_machine import CITIZEN_STATE_LABELS, STATE_GROUPS, resolution_for
from app.text_fold import fold

BBOX = "-91,14,-90,15"


def add(
    client: TestClient,
    *,
    category: str = "pothole",
    state: str = "nuevo",
    note: str | None = None,
    lat: float = 14.5,
    lon: float = -90.5,
) -> str:
    created = datetime.now(UTC) - timedelta(days=1)
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
                verified_at=created,
                state_changed_at=created,
                state=state,
                status="verified",
                resolution=resolution_for(state),
                note=note,
            )
        )
        session.commit()
    return str(report_id)


def ids(client: TestClient, **params: str) -> set[str]:
    response = client.get("/api/reports", params=params)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["total"] == len(body["items"])
    return {item["id"] for item in body["items"]}


def test_fold_strips_case_and_accents() -> None:
    assert fold("Luminaria DAÑADA en la Revisión") == "luminaria danada en la revision"


def test_q_matches_note_category_and_state_labels(client: TestClient) -> None:
    note = add(client, category="graffiti", note="Árbol caído junto al CAFÉ")
    pothole = add(client, category="pothole")
    light = add(client, category="street_light", state="en_revision")
    solved = add(client, category="sidewalk", state="resuelto")

    assert ids(client, q="cafe") == {note}
    assert ids(client, q="ARBOL caido") == {note}
    assert ids(client, q="bache") == {pothole}
    assert ids(client, q="danada") == {light}  # "Luminaria dañada"
    assert ids(client, q="revision") == {light}  # "En revisión"
    assert ids(client, q="resuelto") == {solved}
    assert ids(client, q="  ") == {note, pothole, light, solved}  # blank = no filter
    assert ids(client, q="nada-coincide") == set()


def test_every_word_must_match_some_field(client: TestClient) -> None:
    match = add(client, category="pothole", note="Frente a la escuela")
    add(client, category="pothole", note="Frente al mercado")
    add(client, category="graffiti", note="Pared de la escuela")
    assert ids(client, q="bache escuela") == {match}


def test_q_combines_with_filters_and_paging(client: TestClient) -> None:
    inside = [add(client, note=f"hoyo grande {n}") for n in range(3)]
    add(client, note="hoyo grande lejos", lat=40.0, lon=-3.0)  # outside the bbox
    add(client, category="graffiti", note="hoyo grande pintado")
    add(client, state="resuelto", note="hoyo grande resuelto")

    body = client.get(
        "/api/reports",
        params={
            "q": "Hoyo",
            "bbox": BBOX,
            "category": "pothole",
            "state_group": "open",
            "limit": "2",
            "offset": "0",
        },
    ).json()
    assert body["total"] == 3 and len(body["items"]) == 2
    rest = client.get(
        "/api/reports",
        params={
            "q": "Hoyo",
            "bbox": BBOX,
            "category": "pothole",
            "state_group": "open",
            "limit": "2",
            "offset": "2",
        },
    ).json()
    assert {i["id"] for i in body["items"] + rest["items"]} == set(inside)


def test_q_treats_wildcards_literally_and_hides_hidden(client: TestClient) -> None:
    add(client, note="50% del carril")
    add(client, note="sin porcentaje")
    hidden = add(client, state="oculto", note="oculto secreto")
    assert len(ids(client, q="50%")) == 1
    assert ids(client, q="%") == ids(client, q="50%")
    assert ids(client, q="_") == set()
    assert ids(client, q="secreto") == set()
    enable_staff(client)
    staff = client.get("/api/reports", params={"q": "secreto"}, headers=OPERATOR)
    assert {i["id"] for i in staff.json()["items"]} == {hidden}


def test_q_is_limited_and_not_serialized(client: TestClient) -> None:
    add(client, note="Bache profundo")
    assert client.get("/api/reports", params={"q": "x" * 101}).status_code == 422
    item = client.get("/api/reports", params={"q": "profundo"}).json()["items"][0]
    assert "note_search" not in item and item["note"] == "Bache profundo"


def test_note_search_follows_note_changes(client: TestClient) -> None:
    report_id = add(client, note="Poste caído")
    with client.app.state.services.database.sessions() as session:
        row = session.get(Report, UUID(report_id))
        assert row is not None and row.note_search == "poste caido"
        row.note = None
        session.commit()
        assert row.note_search is None


def test_citizen_state_labels_match_the_app() -> None:
    dart = Path(__file__).parents[3] / "app/lib/core/citizen_states.dart"
    if not dart.is_file():
        pytest.skip("app folder not checked out")
    pairs = dict(
        re.findall(r"'([a-z_]+)': CitizenState\(\s*'([^']+)'", dart.read_text("utf-8"))
    )
    assert pairs == CITIZEN_STATE_LABELS
    assert set(CITIZEN_STATE_LABELS) == set(STATE_GROUPS)


def test_one_report_clusters_carry_pin_fields(client: TestClient) -> None:
    alone = add(
        client, category="street_light", state="en_proceso", lat=14.1, lon=-90.9
    )
    for _ in range(3):
        add(client, lat=14.6, lon=-90.5)
    body = client.get(
        "/api/reports/clusters", params={"bbox": BBOX, "zoom": "10"}
    ).json()
    assert body["total"] == 4
    single = next(c for c in body["clusters"] if c["count"] == 1)
    group = next(c for c in body["clusters"] if c["count"] == 3)
    assert single["ids"] == [alone]
    assert single["category"] == "street_light"
    assert single["state"] == "en_proceso"
    assert single["state_group"] == "in_work"
    assert set(group) == {"lat", "lon", "count", "ids"}


def test_single_report_zoom_clusters_all_carry_pin_fields(client: TestClient) -> None:
    add(client, category="sidewalk", state="resuelto", lat=14.6, lon=-90.5)
    add(client, category="pothole", state="nuevo", lat=14.6001, lon=-90.5)
    clusters = client.get(
        "/api/reports/clusters", params={"bbox": BBOX, "zoom": "16"}
    ).json()["clusters"]
    assert {(c["category"], c["state"], c["state_group"]) for c in clusters} == {
        ("sidewalk", "resuelto", "resolved"),
        ("pothole", "nuevo", "open"),
    }


def test_migration_backfills_note_search(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    url = f"sqlite:///{tmp_path / 'search.db'}"
    monkeypatch.setenv("DATABASE_URL", url)
    config = Config("alembic.ini")
    command.upgrade(config, "0005")
    engine = create_engine(url)
    try:
        with engine.begin() as connection:
            for note in ("Señal CAÍDA", None):
                connection.execute(
                    text(
                        "INSERT INTO reports (id, category, latitude, longitude, "
                        "captured_at, created_at, status, resolution, state, "
                        "state_changed_at, note) VALUES (:id, 'pothole', 14.5, "
                        "-90.5, '2026-11-10 12:00:00', '2026-11-10 12:00:00', "
                        "'verified', 'open', 'nuevo', '2026-11-10 12:00:00', :note)"
                    ),
                    {"id": uuid4().hex, "note": note},
                )
        command.upgrade(config, "head")
        with engine.connect() as connection:
            values = connection.execute(text("SELECT note_search FROM reports"))
            assert {row[0] for row in values} == {None, "senal caida"}
        command.downgrade(config, "0005")
    finally:
        engine.dispose()
