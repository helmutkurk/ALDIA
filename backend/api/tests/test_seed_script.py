import importlib.util
import sys
from collections import Counter
from collections.abc import Iterator
from datetime import UTC, datetime
from pathlib import Path
from types import ModuleType

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import func, select

from app.db import Base, Database
from app.models import Report, ReportEvent
from app.services.storage import PhotoStorage

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "seed_demo.py"


@pytest.fixture(scope="module")
def seed_module() -> Iterator[ModuleType]:
    spec = importlib.util.spec_from_file_location("seed_demo", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["seed_demo"] = module
    spec.loader.exec_module(module)
    yield module
    sys.modules.pop("seed_demo", None)


@pytest.fixture
def env(tmp_path: Path) -> Iterator[tuple[Database, PhotoStorage]]:
    database = Database(f"sqlite:///{tmp_path / 'seed.db'}")
    Base.metadata.create_all(database.engine)
    yield database, PhotoStorage(tmp_path / "photos")
    database.engine.dispose()


def test_seed_covers_states_categories_and_is_idempotent(
    seed_module: ModuleType, env: tuple[Database, PhotoStorage]
) -> None:
    database, storage = env
    now = datetime(2026, 11, 19, 18, 0, tzinfo=UTC)
    with database.sessions() as session:
        first = seed_module.seed(session, storage, now)
        assert first == {"created": sum(seed_module.PLAN.values()), "skipped": 0}
        again = seed_module.seed(session, storage, now)
        assert again["created"] == 0
        reports = list(session.scalars(select(Report)))
        assert len(reports) == sum(seed_module.PLAN.values())
        assert Counter(r.state for r in reports) == Counter(seed_module.PLAN)
        assert {r.category for r in reports} == {
            "accessibility",
            "sidewalk",
            "pothole",
            "graffiti",
            "open_drain",
            "street_light",
        }
        assert all(r.note and r.note.startswith("[demo]") for r in reports)
        assert all(storage.path(r.id).exists() for r in reports)
        # Spread over roughly 60 days, nothing in the future, GT bounding area.
        ages = [(now - r.created_at.replace(tzinfo=UTC)).days for r in reports]
        assert min(ages) >= 0 and max(ages) >= 30
        assert all(
            14.5 < r.latitude < 14.8 and -90.7 < r.longitude < -90.3 for r in reports
        )
        # Duplicates point at an existing master of the same category.
        by_id = {r.id: r for r in reports}
        dups = [r for r in reports if r.state == "duplicado"]
        assert dups and all(
            r.duplicate_of in by_id and by_id[r.duplicate_of].category == r.category
            for r in dups
        )
        # Event chains are ordered and end in the report's current state.
        for report in reports:
            events = list(
                session.scalars(
                    select(ReportEvent)
                    .where(ReportEvent.report_id == report.id)
                    .order_by(ReportEvent.at, ReportEvent.id)
                )
            )
            assert events[0].to_state == "pendiente_verificacion"
            times = [e.at.replace(tzinfo=UTC) for e in events]
            assert times == sorted(times) and times[-1] <= now
            assert events[-1].to_state == report.state
            for earlier, later in zip(events, events[1:], strict=False):
                assert later.from_state == earlier.to_state
        assert session.scalar(select(func.count()).select_from(ReportEvent)) > len(
            reports
        )
    with Image.open(storage.path(reports[0].id)) as image:
        assert image.size == (800, 600) and image.format == "JPEG"


def test_seeded_reports_are_served_by_the_api(
    seed_module: ModuleType, client: TestClient
) -> None:
    services = client.app.state.services  # type: ignore[attr-defined]
    with services.database.sessions() as session:
        seed_module.seed(session, services.storage)
    listing = client.get("/api/reports", params={"include_old": "true", "limit": 100})
    assert listing.status_code == 200
    assert listing.json()["total"] >= 40  # hidden reports are excluded
    states = client.get("/api/stats", params={"include_old": "true"}).json()["by_state"]
    assert states["resuelto"] == 8
    first = listing.json()["items"][0]
    assert client.get(first["photo_url"]).status_code == 200


def test_purge_removes_only_demo_rows(
    seed_module: ModuleType, env: tuple[Database, PhotoStorage]
) -> None:
    database, storage = env
    with database.sessions() as session:
        session.add(
            Report(
                id=seed_module.uuid5(seed_module.NAMESPACE, "real"),
                category="pothole",
                latitude=14.6,
                longitude=-90.5,
                captured_at=datetime.now(UTC),
                created_at=datetime.now(UTC),
                status="pending",
                note="real note",
            )
        )
        session.commit()
        seed_module.seed(session, storage)
        removed = seed_module.purge(session, storage)
        assert removed == sum(seed_module.PLAN.values())
        assert session.scalar(select(func.count()).select_from(Report)) == 1
        assert not list(storage.root.glob("*.jpg"))


def test_refuses_production(
    seed_module: ModuleType,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setenv("ALDIA_ENV", "Production")
    assert seed_module.main([]) == 2
    assert "Refusing" in capsys.readouterr().err
    with pytest.raises(seed_module.ProductionRefused):
        seed_module.refuse_production({"APP_ENV": "prod"})
    seed_module.refuse_production({"APP_ENV": "development"})
