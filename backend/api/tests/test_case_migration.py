from pathlib import Path
from uuid import uuid4

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text

from alembic import command


def test_case_migration_backfill_and_downgrade(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    url = f"sqlite:///{tmp_path / 'cases.db'}"
    monkeypatch.setenv("DATABASE_URL", url)
    config = Config("alembic.ini")
    command.upgrade(config, "0002")
    engine = create_engine(url)
    try:
        pairs = [
            ("pending", "open", "pendiente_verificacion", "open"),
            ("rejected", "open", "rechazado_verificador", "closed"),
            ("verified", "open", "nuevo", "open"),
            ("verified", "acknowledged", "en_proceso", "acknowledged"),
            ("verified", "fixed", "resuelto", "fixed"),
        ]
        with engine.begin() as connection:
            for status, resolution, _, _ in pairs:
                connection.execute(
                    text(
                        "INSERT INTO reports (id, category, latitude, longitude, "
                        "captured_at, created_at, status, resolution) VALUES "
                        "(:id, 'pothole', 14.5, -90.5, '2026-11-10 12:00:00', "
                        "'2026-11-10 12:00:00', :status, :resolution)"
                    ),
                    {"id": uuid4().hex, "status": status, "resolution": resolution},
                )
        command.upgrade(config, "head")
        with engine.connect() as connection:
            rows = connection.execute(text("SELECT * FROM reports")).mappings().all()
            for row in rows:
                expected = next(
                    p
                    for p in pairs
                    if p[0] == row["status"] and p[3] == row["resolution"]
                )
                assert row["state"] == expected[2]
                assert row["state_changed_at"] == row["created_at"]
                assert (row["verified_at"] is None) == (row["status"] == "pending")
                assert (row["resolved_at"] is not None) == (row["state"] == "resuelto")
            assert connection.scalar(text("SELECT count(*) FROM report_events")) == 5
            assert (
                connection.scalar(text("SELECT count(*) FROM idempotency_records")) == 0
            )
        indexes = {index["name"] for index in inspect(engine).get_indexes("reports")}
        assert {
            "ix_reports_state",
            "ix_reports_created_at",
            "ix_reports_category_state",
            "ix_reports_location",
        } <= indexes
        command.check(config)
        command.downgrade(config, "0002")
        assert "report_events" not in inspect(engine).get_table_names()
        assert "idempotency_records" not in inspect(engine).get_table_names()
        with engine.connect() as connection:
            assert connection.scalar(text("SELECT count(*) FROM reports")) == 5
            assert (
                connection.scalar(
                    text("SELECT count(*) FROM reports WHERE resolution='closed'")
                )
                == 0
            )
    finally:
        engine.dispose()
