"""Case- and accent-insensitive text search for the public report list.

Every word of `q` must match at least one of: the category label, the citizen state
label, or the note. Labels are a small fixed set and are matched in Python; notes are
matched in SQL against `Report.note_search`, a folded copy kept by the model, so the
search behaves the same on SQLite and PostgreSQL without database extensions.
"""

from sqlalchemy import Select, and_, or_

from app.categories import CATEGORIES
from app.models import Report
from app.state_machine import CITIZEN_STATE_LABELS
from app.text_fold import fold

MAX_TERMS = 8


def search_terms(q: str | None) -> list[str]:
    return fold(q).split()[:MAX_TERMS] if q else []


def _like_pattern(term: str) -> str:
    escaped = term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{escaped}%"


_FOLDED_CATEGORIES = tuple((code, fold(label)) for code, label in CATEGORIES)
_FOLDED_STATES = tuple(
    (state, fold(label)) for state, label in CITIZEN_STATE_LABELS.items()
)


def with_text_search(
    query: Select[tuple[Report]], q: str | None
) -> Select[tuple[Report]]:
    terms = search_terms(q)
    if not terms:
        return query
    conditions = []
    for term in terms:
        categories = [code for code, label in _FOLDED_CATEGORIES if term in label]
        states = [state for state, label in _FOLDED_STATES if term in label]
        alternatives = [Report.note_search.like(_like_pattern(term), escape="\\")]
        if categories:
            alternatives.append(Report.category.in_(categories))
        if states:
            alternatives.append(Report.state.in_(states))
        conditions.append(or_(*alternatives))
    return query.where(and_(*conditions))
