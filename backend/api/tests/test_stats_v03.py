"""Hand-computed v0.3 cohorts, durations and deterministic ranking."""

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from test_stats_v02 import add_report


def test_category_counts_durations_and_top_five(client: TestClient) -> None:
    start = datetime(2026, 11, 10, 6, tzinfo=UTC)
    for category, hours in [
        ("pothole", [0, 2, 10, 20]),
        ("sidewalk", [1, 3, 5]),
        ("graffiti", [9]),
    ]:
        for value in hours:
            add_report(
                client,
                created=start,
                state="resuelto",
                verified=start,
                resolved=start + timedelta(hours=value),
                category=category,
            )
    for state in ["pendiente_verificacion", "nuevo", "programado", "en_proceso"]:
        add_report(client, created=start, state=state)
    for state in [
        "rechazado_verificador",
        "no_procede",
        "fuera_de_competencia",
        "duplicado",
    ]:
        add_report(client, created=start, state=state, verified=start)
    # Incomplete legacy resolution: resolved, but no duration sample.
    add_report(client, created=start, state="resuelto", category="open_drain")
    # A stale resolved_at on a reopened case must never supply a repair sample.
    add_report(
        client,
        created=start,
        state="en_revision",
        verified=start,
        resolved=start + timedelta(hours=100),
        category="street_light",
    )
    add_report(client, created=start, state="oculto", verified=start)
    data = client.get("/api/stats?include_old=true").json()
    rows = {r["category"]: r for r in data["por_categoria"]}
    assert list(rows) == sorted(rows)
    assert rows["pothole"] == {
        "category": "pothole",
        "total": 12,
        "resueltos": 4,
        "abiertos": 4,
        "cerrados": 4,
        "mediana_reparacion_horas": 6,
        "p90_reparacion_horas": 17,
        "n_resueltos": 4,
    }
    assert rows["sidewalk"]["mediana_reparacion_horas"] == 3
    assert rows["sidewalk"]["p90_reparacion_horas"] == pytest.approx(4.6)
    assert rows["graffiti"]["mediana_reparacion_horas"] == 9
    assert rows["graffiti"]["p90_reparacion_horas"] == 9
    assert rows["open_drain"]["resueltos"] == 1
    for category in ["accessibility", "open_drain", "street_light"]:
        assert rows[category]["mediana_reparacion_horas"] is None
        assert rows[category]["p90_reparacion_horas"] is None
        assert rows[category]["n_resueltos"] == 0
    assert [r["category"] for r in data["top_categorias"]] == [
        "pothole",
        "sidewalk",
        "graffiti",
        "open_drain",
        "street_light",
    ]
    assert all(r == rows[r["category"]] for r in data["top_categorias"])
    assert sum(r["total"] for r in rows.values()) == data["total"] == 18
    assert all(
        r["total"] == r["resueltos"] + r["abiertos"] + r["cerrados"]
        for r in rows.values()
    )
    assert "por_municipio_zona" not in data
    # Six populated categories: truncate to five and break ties by category id.
    add_report(client, created=start, state="nuevo", category="accessibility")
    ranked = client.get("/api/stats?include_old=true").json()["top_categorias"]
    assert [r["category"] for r in ranked] == [
        "pothole",
        "sidewalk",
        "accessibility",
        "graffiti",
        "open_drain",
    ]


def test_category_filters_and_creation_window(client: TestClient) -> None:
    start = datetime(2026, 11, 10, 6, tzinfo=UTC)
    for created, category, assignee in [
        (start, "pothole", "Equipo A"),
        (start - timedelta(seconds=1), "pothole", "Equipo A"),
        (start + timedelta(days=1), "pothole", "Equipo A"),
        (start, "graffiti", "Equipo A"),
        (start, "pothole", "Equipo B"),
    ]:
        add_report(
            client,
            created=created,
            state="resuelto",
            verified=created,
            resolved=start + timedelta(days=2),
            category=category,
            assignee=assignee,
        )
    data = client.get(
        "/api/stats",
        params={
            "created_from": "2026-11-10",
            "created_to": "2026-11-10",
            "category": "pothole",
            "assignee": "Equipo A",
            "state_group": "resolved",
            "status": "verified",
            "resolution": "fixed",
            "bbox": "-91,14,-90,15",
        },
    ).json()
    # Resolved AFTER the selected day, but created within it: 48h.
    assert data["top_categorias"] == [
        {
            "category": "pothole",
            "total": 1,
            "resueltos": 1,
            "abiertos": 0,
            "cerrados": 0,
            "mediana_reparacion_horas": 48,
            "p90_reparacion_horas": 48,
            "n_resueltos": 1,
        }
    ]
    assert data["resueltos"] == 0  # v0.2 resolution-period semantics preserved
    assert data["by_category"]["pothole"] == 1
    empty = client.get("/api/stats", params={"bbox": "0,0,1,1"}).json()
    assert empty["top_categorias"] == []
    assert len(empty["por_categoria"]) == 6
    assert all(r["total"] == r["n_resueltos"] == 0 for r in empty["por_categoria"])
