"""Text folding shared by the model and the search (no app imports, no cycles)."""

import unicodedata


def fold(text: str) -> str:
    """Lowercase and strip accents: 'Luminaria DAÑADA' -> 'luminaria danada'."""
    decomposed = unicodedata.normalize("NFKD", text)
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    return stripped.casefold()
