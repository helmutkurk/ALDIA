"""Add the government's report resolution state.

Revision ID: 0002
Revises: 0001
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0002"
down_revision: str | Sequence[str] | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Batch mode also supports the SQLite databases used for local development.
    with op.batch_alter_table("reports") as batch:
        batch.add_column(
            sa.Column(
                "resolution", sa.String(16), nullable=False, server_default="open"
            )
        )
        batch.create_check_constraint(
            "ck_reports_resolution", "resolution IN ('open', 'acknowledged', 'fixed')"
        )


def downgrade() -> None:
    with op.batch_alter_table("reports") as batch:
        batch.drop_constraint("ck_reports_resolution", type_="check")
        batch.drop_column("resolution")
