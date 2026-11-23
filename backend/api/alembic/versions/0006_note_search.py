"""Add a folded copy of the note for case- and accent-insensitive search."""

import unicodedata

import sqlalchemy as sa

from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def _fold(text: str) -> str:
    # Frozen copy of app.text_search.fold: migrations must not import app code.
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(c for c in decomposed if not unicodedata.combining(c)).casefold()


def upgrade() -> None:
    with op.batch_alter_table("reports") as batch:
        batch.add_column(sa.Column("note_search", sa.Text()))
    connection = op.get_bind()
    reports = sa.table(
        "reports",
        sa.column("id", sa.Uuid()),
        sa.column("note", sa.String(280)),
        sa.column("note_search", sa.Text()),
    )
    rows = connection.execute(
        sa.select(reports.c.id, reports.c.note).where(reports.c.note.is_not(None))
    ).all()
    for report_id, note in rows:
        connection.execute(
            reports.update()
            .where(reports.c.id == report_id)
            .values(note_search=_fold(note))
        )


def downgrade() -> None:
    with op.batch_alter_table("reports") as batch:
        batch.drop_column("note_search")
