import csv
from datetime import UTC, datetime, timedelta
from io import StringIO
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from app.models import Report, ReportEvent
from app.state_machine import resolution_for


def add_report(
    client: TestClient,
    *,
    created: datetime,
    state: str,
    verified: datetime | None = None,
    resolved: datetime | None = None,
    closed: datetime | None = None,
    category: str = "pothole",
    assignee: str | None = None,
) -> UUID:
    identifier = uuid4()
    with client.app.state.services.database.sessions() as session:
        session.add(
            Report(
                id=identifier,
                category=category,
                latitude=14.5,
                longitude=-90.5,
                captured_at=created,
                created_at=created,
                state=state,
                state_changed_at=resolved or closed or created,
                status="pending"
                if verified is None
                else "rejected"
                if state == "rechazado_verificador"
                else "verified",
                resolution=resolution_for(state),
                verified_at=verified,
                resolved_at=resolved,
                closed_at=closed,
                assignee=assignee,
            )
        )
        session.commit()
    return identifier


def test_hand_computed_dashboard_and_local_day_boundaries(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    import app.routes.stats as stats_module

    class FrozenDateTime(datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2026, 11, 20, 6, tzinfo=UTC)

    monkeypatch.setattr(stats_module, "datetime", FrozenDateTime)
    start = datetime(2026, 11, 10, 6, tzinfo=UTC)  # midnight in Guatemala
    # Two cohort resolutions: 2h and 10h, one older report resolved in period: 300h.
    a = add_report(
        client,
        created=start,
        state="resuelto",
        verified=start,
        resolved=start + timedelta(hours=2),
    )
    b = add_report(
        client,
        created=start + timedelta(days=1),
        state="resuelto",
        verified=start + timedelta(days=1),
        resolved=start + timedelta(days=1, hours=10),
    )
    add_report(
        client,
        created=start - timedelta(days=15),
        state="resuelto",
        verified=start - timedelta(hours=299),
        resolved=start + timedelta(hours=1),
    )
    add_report(
        client,
        created=start,
        state="duplicado",
        verified=start,
        closed=start + timedelta(hours=3),
    )
    add_report(
        client,
        created=start,
        state="fuera_de_competencia",
        verified=start,
        closed=start + timedelta(hours=4),
    )
    add_report(
        client,
        created=start,
        state="no_procede",
        verified=start,
        closed=start + timedelta(hours=5),
    )
    add_report(
        client,
        created=start,
        state="rechazado_verificador",
        verified=start,
        closed=start,
    )
    add_report(client, created=start, state="pendiente_verificacion")
    add_report(
        client, created=start, state="nuevo", verified=start, category="open_drain"
    )  # 240h, overdue (72h)
    # Public hidden and outside local date boundary must contribute nothing.
    add_report(client, created=start, state="oculto", verified=start)
    add_report(
        client, created=start - timedelta(seconds=1), state="nuevo", verified=start
    )
    add_report(
        client,
        created=datetime(2026, 11, 20, 6, tzinfo=UTC),
        state="nuevo",
        verified=start,
    )
    with client.app.state.services.database.sessions() as session:
        for report_id, hours in [(a, 1), (b, 3)]:
            verified = start if report_id == a else start + timedelta(days=1)
            session.add(
                ReportEvent(
                    report_id=report_id,
                    actor_role="system",
                    from_state="pendiente_verificacion",
                    to_state="nuevo",
                    at=verified,
                )
            )
            session.add(
                ReportEvent(
                    report_id=report_id,
                    actor_role="operator",
                    from_state="nuevo",
                    to_state="en_revision",
                    at=verified + timedelta(hours=hours),
                )
            )
            session.add(
                ReportEvent(
                    report_id=report_id,
                    actor_role="supervisor",
                    from_state="en_revision",
                    to_state="en_proceso",
                    at=verified + timedelta(hours=hours + 1),
                )
            )
        session.commit()
    response = client.get("/api/stats?created_from=2026-11-10&created_to=2026-11-19")
    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 8
    assert data["recibidos"] == 7  # includes verifier rejection, excludes pending
    assert data["rechazados_verificador"] == 1
    assert data["abiertos"] == 1
    assert data["resueltos"] == 3  # includes pre-period creation resolved in period
    assert data["cerrados_sin_solucion"] == 3
    assert (
        data["tasa_resolucion"] == 0.4
    )  # 2 / (7 - 1 duplicate - 1 outside jurisdiction)
    assert data["tasa_resolucion_n"] == 5
    assert data["resolucion_horas"] == {"median": 10, "p90": 242, "mean": 104, "n": 3}
    assert data["primera_respuesta_horas"] == {"median": 2, "p90": 2.8, "n": 2}
    assert data["sla_cumplido"] == pytest.approx(2 / 3)
    assert data["vencidos"] == 1
    assert data["antiguedad_abiertos"] == {"0-2": 0, "3-7": 0, "8-30": 1, ">30": 0}
    assert data["weekly"] == [{"week": "2026-W46", "recibidos": 7, "resueltos": 3}]
    assert data["by_state_group"]["closed"] == 4
    assert data["by_state_group"]["hidden"] == 0
    assert sum(data["by_category"].values()) == data["total"]


def test_empty_metrics_and_age_buckets(client: TestClient) -> None:
    empty = client.get("/api/stats").json()
    assert empty["tasa_resolucion"] is empty["sla_cumplido"] is None
    assert empty["resolucion_horas"] == {
        "median": None,
        "p90": None,
        "mean": None,
        "n": 0,
    }
    assert empty["primera_respuesta_horas"] == {"median": None, "p90": None, "n": 0}
    now = datetime.now(UTC)
    for days in [0, 2.9, 3, 7.9, 8, 30.9, 31]:
        created = now - timedelta(days=days)
        add_report(client, created=created, state="nuevo", verified=created)
    data = client.get("/api/stats?include_old=true").json()
    assert data["antiguedad_abiertos"] == {"0-2": 2, "3-7": 2, "8-30": 2, ">30": 1}
    assert data["abiertos"] == 7
    assert data["resueltos"] == 0
    assert data["tasa_resolucion"] == 0


def test_csv_bom_delimiters_and_derived_cells(client: TestClient) -> None:
    created = datetime.now(UTC) - timedelta(days=2)
    identifier = add_report(
        client,
        created=created,
        state="resuelto",
        verified=created,
        resolved=created + timedelta(hours=48),
        assignee='=SUM(1,2);"equipo"\nñ',
    )
    duplicate = add_report(
        client, created=created, state="duplicado", verified=created, closed=created
    )
    hidden_duplicate = add_report(
        client, created=created, state="oculto", verified=created
    )
    with client.app.state.services.database.sessions() as session:
        session.get(Report, duplicate).duplicate_of = identifier
        session.get(Report, hidden_duplicate).duplicate_of = identifier
        session.commit()
    for delimiter, char in [("comma", ","), ("semicolon", ";")]:
        response = client.get(f"/api/reports.csv?delimiter={delimiter}")
        assert response.status_code == 200
        assert response.content.startswith(b"\xef\xbb\xbf")
        rows = list(
            csv.DictReader(
                StringIO(response.content.decode("utf-8-sig")), delimiter=char
            )
        )
        assert len(rows) == 2
        row = next(r for r in rows if r["id"] == str(identifier))
        assert list(row) == [
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
        assert row["assignee"] == '\'=SUM(1,2);"equipo"\nñ'
        assert row["longitude"] == "-90.5"  # numeric cells never prefixed
        assert row["duplicates_count"] == "1"
        assert float(row["days_open"]) == 2
        assert row["link"] == f"/api/reports/{identifier}"


def test_default_window_and_stable_sorting(client: TestClient) -> None:
    now = datetime.now(UTC)
    old = add_report(
        client,
        created=now - timedelta(days=100),
        state="nuevo",
        verified=now - timedelta(days=100),
    )
    first = add_report(
        client, created=now - timedelta(days=2), state="nuevo", verified=now
    )
    second = add_report(
        client, created=now - timedelta(days=1), state="en_revision", verified=now
    )
    assert client.get("/api/reports").json()["total"] == 2
    assert client.get("/api/reports?include_old=true").json()["total"] == 3
    assert client.get("/api/stats").json()["total"] == 2
    assert str(old) not in client.get("/api/reports.csv").text
    assert [
        r["id"] for r in client.get("/api/reports?sort=oldest").json()["items"]
    ] == [str(first), str(second)]
    assert [
        r["id"] for r in client.get("/api/reports?sort=age_in_state").json()["items"]
    ] == [str(first), str(second)]
    with client.app.state.services.database.sessions() as session:
        session.add(
            ReportEvent(
                report_id=first,
                actor_role="operator",
                from_state="nuevo",
                to_state="en_revision",
                public_note="Recibido",
                at=now - timedelta(hours=1),
            )
        )
        session.add(
            ReportEvent(
                report_id=second,
                actor_role="operator",
                from_state="en_revision",
                to_state="en_proceso",
                internal_note="Privado",
                at=now,
            )
        )
        session.commit()
    assert [
        r["id"] for r in client.get("/api/reports?sort=updated").json()["items"]
    ] == [str(first), str(second)]
