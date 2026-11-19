"""Add municipality case state, audit events and retry keys.

Revision ID: 0003
Revises: 0002

Legacy data has no historical workflow clock. Backfilled event/timing values use
creation time as an explicit approximation, not a reconstructed staff history.
"""

from collections.abc import Sequence
from uuid import uuid4

import sqlalchemy as sa

from alembic import op

revision: str = "0003"
down_revision: str | Sequence[str] | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("reports") as batch:
        batch.drop_constraint("ck_reports_resolution", type_="check")
        batch.create_check_constraint(
            "ck_reports_resolution",
            "resolution IN ('open', 'acknowledged', 'fixed', 'closed')",
        )
        batch.add_column(
            sa.Column(
                "state",
                sa.String(32),
                nullable=False,
                server_default="pendiente_verificacion",
            )
        )
        batch.add_column(sa.Column("state_changed_at", sa.DateTime(timezone=True)))
        for name in ("verified_at", "resolved_at", "closed_at", "assigned_at"):
            batch.add_column(sa.Column(name, sa.DateTime(timezone=True)))
        batch.add_column(sa.Column("assignee", sa.String(60)))
        batch.add_column(sa.Column("duplicate_of", sa.Uuid()))
        batch.add_column(sa.Column("public_note", sa.String(280)))
        batch.add_column(sa.Column("previous_state", sa.String(32)))
        batch.create_foreign_key(
            "fk_reports_duplicate_of", "reports", ["duplicate_of"], ["id"]
        )

    connection = op.get_bind()
    connection.execute(
        sa.text("""
        UPDATE reports SET
          state = CASE
            WHEN status = 'pending' THEN 'pendiente_verificacion'
            WHEN status = 'rejected' THEN 'rechazado_verificador'
            WHEN resolution = 'fixed' THEN 'resuelto'
            WHEN resolution = 'acknowledged' THEN 'en_proceso'
            ELSE 'nuevo' END,
          state_changed_at = created_at,
          verified_at = CASE WHEN status != 'pending' THEN created_at ELSE NULL END,
          resolved_at = CASE WHEN status = 'verified' AND resolution = 'fixed'
            THEN created_at ELSE NULL END,
          closed_at = CASE WHEN status = 'rejected' THEN created_at ELSE NULL END,
          resolution = CASE WHEN status = 'rejected' THEN 'closed'
            WHEN status = 'pending' THEN 'open' ELSE resolution END
    """)
    )
    with op.batch_alter_table("reports") as batch:
        batch.alter_column(
            "state_changed_at", existing_type=sa.DateTime(timezone=True), nullable=False
        )
        batch.create_index("ix_reports_state", ["state"])
        batch.create_index("ix_reports_category_state", ["category", "state"])
        batch.create_index("ix_reports_location", ["latitude", "longitude"])

    events = op.create_table(
        "report_events",
        sa.Column("id", sa.Uuid(), nullable=False, primary_key=True),
        sa.Column("report_id", sa.Uuid(), sa.ForeignKey("reports.id"), nullable=False),
        sa.Column("actor_role", sa.String(16), nullable=False),
        sa.Column("from_state", sa.String(32)),
        sa.Column("to_state", sa.String(32), nullable=False),
        sa.Column("public_note", sa.String(280)),
        sa.Column("internal_note", sa.String(500)),
        sa.Column("at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_report_events_report_at", "report_events", ["report_id", "at", "id"]
    )
    reports = sa.table(
        "reports",
        sa.column("id", sa.Uuid()),
        sa.column("state", sa.String()),
        sa.column("created_at", sa.DateTime(timezone=True)),
    )
    # Insert in bounded batches to avoid loading a municipality's entire history.
    buffer: list[dict[str, object]] = []
    for report in connection.execute(sa.select(reports)):
        buffer.append(
            {
                "id": uuid4(),
                "report_id": report.id,
                "actor_role": "system",
                "from_state": None,
                "to_state": report.state,
                "public_note": None,
                "internal_note": (
                    "Estado migrado desde v0.1; las fechas históricas "
                    "aproximan la creación."
                ),
                "at": report.created_at,
            }
        )
        if len(buffer) >= 1000:
            connection.execute(events.insert(), buffer)
            buffer.clear()
    if buffer:
        connection.execute(events.insert(), buffer)
    op.create_table(
        "idempotency_records",
        sa.Column("key", sa.Uuid(), nullable=False, primary_key=True),
        sa.Column("report_id", sa.Uuid(), sa.ForeignKey("reports.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_idempotency_records_created_at", "idempotency_records", ["created_at"]
    )


def downgrade() -> None:
    op.drop_table("idempotency_records")
    op.drop_table("report_events")
    op.execute("UPDATE reports SET resolution = 'open' WHERE resolution = 'closed'")
    with op.batch_alter_table("reports") as batch:
        batch.drop_index("ix_reports_state")
        batch.drop_index("ix_reports_category_state")
        batch.drop_index("ix_reports_location")
        batch.drop_constraint("fk_reports_duplicate_of", type_="foreignkey")
        batch.drop_constraint("ck_reports_resolution", type_="check")
        batch.create_check_constraint(
            "ck_reports_resolution", "resolution IN ('open', 'acknowledged', 'fixed')"
        )
        for name in (
            "state",
            "state_changed_at",
            "verified_at",
            "resolved_at",
            "closed_at",
            "assignee",
            "assigned_at",
            "duplicate_of",
            "public_note",
            "previous_state",
        ):
            batch.drop_column(name)
