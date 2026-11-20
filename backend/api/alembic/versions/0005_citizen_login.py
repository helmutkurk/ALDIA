"""Add hashed citizen identities, challenges, device sessions and report ownership."""

import sqlalchemy as sa

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "citizens",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("phone_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("phone_last2", sa.String(2), nullable=False),
        sa.Column("alias", sa.String(60)),
        sa.Column("alias_public", sa.Boolean(), nullable=False, server_default="0"),
    )
    op.create_table(
        "citizen_challenges",
        sa.Column("phone_hash", sa.String(64), primary_key=True),
        sa.Column("phone_last2", sa.String(2), nullable=False),
        sa.Column("device_hash", sa.String(64), nullable=False),
        sa.Column("nonce", sa.String(32), nullable=False),
        sa.Column("code_hash", sa.String(64), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_citizen_challenges_expires_at", "citizen_challenges", ["expires_at"]
    )
    op.create_table(
        "citizen_sessions",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "citizen_id", sa.String(64), sa.ForeignKey("citizens.id"), nullable=False
        ),
        sa.Column("device_hash", sa.String(64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_citizen_sessions_owner_device",
        "citizen_sessions",
        ["citizen_id", "device_hash"],
        unique=True,
    )
    op.create_index(
        "ix_citizen_sessions_expires_at", "citizen_sessions", ["expires_at"]
    )
    with op.batch_alter_table("reports") as batch:
        batch.add_column(sa.Column("citizen_id", sa.String(64)))
        batch.add_column(sa.Column("citizen_alias", sa.String(60)))
        batch.create_foreign_key(
            "fk_reports_citizen_id", "citizens", ["citizen_id"], ["id"]
        )
        batch.create_index("ix_reports_citizen_id", ["citizen_id"])


def downgrade() -> None:
    with op.batch_alter_table("reports") as batch:
        batch.drop_index("ix_reports_citizen_id")
        batch.drop_constraint("fk_reports_citizen_id", type_="foreignkey")
        batch.drop_column("citizen_alias")
        batch.drop_column("citizen_id")
    op.drop_table("citizen_sessions")
    op.drop_table("citizen_challenges")
    op.drop_table("citizens")
