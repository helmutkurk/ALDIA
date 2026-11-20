"""Add staff accounts, revocable sessions and identified audit events."""

import sqlalchemy as sa

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "staff_users",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("username", sa.String(64), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("role", sa.String(16), nullable=False),
        sa.Column("disabled", sa.Boolean(), nullable=False, server_default="0"),
        sa.Column("failed_attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("locked_until", sa.DateTime(timezone=True)),
        sa.CheckConstraint(
            "role IN ('operator', 'supervisor', 'admin')", name="ck_staff_users_role"
        ),
    )
    op.create_table(
        "staff_sessions",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("staff_users.id"), nullable=False
        ),
        sa.Column("signing_key", sa.String(64), nullable=False),
        sa.Column("csrf_hash", sa.String(64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_staff_sessions_user_id", "staff_sessions", ["user_id"])
    op.create_index("ix_staff_sessions_expires_at", "staff_sessions", ["expires_at"])
    op.create_table(
        "auth_events",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("actor", sa.String(80), nullable=False),
        sa.Column("actor_role", sa.String(16), nullable=False),
        sa.Column("action", sa.String(32), nullable=False),
        sa.Column("target", sa.String(64)),
        sa.Column("at", sa.DateTime(timezone=True), nullable=False),
    )
    with op.batch_alter_table("report_events") as batch:
        batch.add_column(
            sa.Column("actor", sa.String(80), nullable=False, server_default="system")
        )
    op.execute(
        "UPDATE report_events SET actor = 'legacy:' || actor_role "
        "WHERE actor_role <> 'system'"
    )


def downgrade() -> None:
    with op.batch_alter_table("report_events") as batch:
        batch.drop_column("actor")
    op.drop_table("auth_events")
    op.drop_table("staff_sessions")
    op.drop_table("staff_users")
