"""Shared fixtures.

By default every test uses its own SQLite file. Set TEST_POSTGRES_URL to an admin
URL of a disposable PostgreSQL server (for example the `db` service of
docker-compose) to run the same tests against PostgreSQL: each test then gets a
fresh database that is dropped afterwards. Never point it at real data.
"""

import os
import uuid
from collections.abc import Callable, Iterator
from pathlib import Path

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from test_reports import client as client  # noqa: F401  (shared fixture)

DatabaseUrl = Callable[[str], str]
POSTGRES_ADMIN_URL = os.environ.get("TEST_POSTGRES_URL", "").strip()


def _admin_execute(statement: str) -> None:
    engine = create_engine(POSTGRES_ADMIN_URL, isolation_level="AUTOCOMMIT")
    try:
        with engine.connect() as connection:
            connection.execute(text(statement))
    finally:
        engine.dispose()


@pytest.fixture
def database_url(tmp_path: Path) -> Iterator[DatabaseUrl]:
    """Return a factory for empty test databases (SQLite or PostgreSQL)."""
    created: list[str] = []

    def make(name: str) -> str:
        if not POSTGRES_ADMIN_URL:
            return f"sqlite:///{tmp_path / f'{name}.db'}"
        database = f"aldia_test_{uuid.uuid4().hex[:12]}"
        _admin_execute(f'CREATE DATABASE "{database}"')
        created.append(database)
        url = make_url(POSTGRES_ADMIN_URL).set(database=database)
        return url.render_as_string(hide_password=False)

    yield make
    for database in created:
        _admin_execute(f'DROP DATABASE IF EXISTS "{database}" WITH (FORCE)')
