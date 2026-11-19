"""Create reports and query indexes.

Revision ID: 0001
Revises: None
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0001"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "reports",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("category", sa.String(32), nullable=False),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("note", sa.String(280), nullable=True),
        sa.Column("phash", sa.String(16), nullable=True),
        sa.Column("verification", sa.JSON(none_as_null=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.CheckConstraint(
            "latitude >= -90 AND latitude <= 90", name="ck_reports_latitude"
        ),
        sa.CheckConstraint(
            "longitude >= -180 AND longitude <= 180", name="ck_reports_longitude"
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'verified', 'rejected')", name="ck_reports_status"
        ),
    )
    op.create_index("ix_reports_created_at", "reports", ["created_at", "id"])
    op.create_index(
        "ix_reports_category_location", "reports", ["category", "latitude", "longitude"]
    )
    op.create_index("ix_reports_status", "reports", ["status"])


def downgrade() -> None:
    op.drop_index("ix_reports_status", table_name="reports")
    op.drop_index("ix_reports_category_location", table_name="reports")
    op.drop_index("ix_reports_created_at", table_name="reports")
    op.drop_table("reports")
