"""Pure case-state policy; persistence and timestamps belong to the caller."""

from dataclasses import dataclass
from typing import Literal

State = Literal[
    "pendiente_verificacion",
    "rechazado_verificador",
    "nuevo",
    "en_revision",
    "programado",
    "en_proceso",
    "resuelto",
    "no_procede",
    "fuera_de_competencia",
    "duplicado",
    "oculto",
]
StateGroup = Literal["pending", "open", "in_work", "resolved", "closed", "hidden"]

STATE_GROUPS: dict[str, str] = {
    "pendiente_verificacion": "pending",
    "rechazado_verificador": "closed",
    "nuevo": "open",
    "en_revision": "open",
    "programado": "in_work",
    "en_proceso": "in_work",
    "resuelto": "resolved",
    "no_procede": "closed",
    "fuera_de_competencia": "closed",
    "duplicado": "closed",
    "oculto": "hidden",
}
OPEN_STATES = ("nuevo", "en_revision", "programado", "en_proceso")
_FLOW = (*OPEN_STATES, "resuelto")


class InvalidTransition(ValueError):
    """The transition or required explanation violates the case policy."""


class RoleForbidden(PermissionError):
    """The actor cannot perform this otherwise valid transition."""


@dataclass(frozen=True)
class Rule:
    roles: frozenset[str] = frozenset({"operator", "supervisor"})
    note_required: bool = False
    internal_required: bool = False


_SUPERVISOR = frozenset({"supervisor"})
_RULES: dict[tuple[str, str], Rule] = {
    ("pendiente_verificacion", "nuevo"): Rule(frozenset({"system"})),
    ("pendiente_verificacion", "rechazado_verificador"): Rule(frozenset({"system"})),
    ("rechazado_verificador", "nuevo"): Rule(_SUPERVISOR, internal_required=True),
    ("en_revision", "no_procede"): Rule(note_required=True),
    ("en_revision", "fuera_de_competencia"): Rule(note_required=True),
    ("en_revision", "duplicado"): Rule(),
    ("programado", "no_procede"): Rule(note_required=True),
    ("resuelto", "en_revision"): Rule(_SUPERVISOR),
    **{
        (state, "en_revision"): Rule(_SUPERVISOR, note_required=True)
        for state in ("no_procede", "fuera_de_competencia", "duplicado")
    },
    **{
        (source, target): Rule(note_required=target_index - source_index > 1)
        for source_index, source in enumerate(_FLOW)
        for target_index, target in enumerate(_FLOW)
        if target_index > source_index
    },
    **{
        (source, target): Rule()
        for source_index, source in enumerate(OPEN_STATES)
        for target in OPEN_STATES[:source_index]
    },
    **{
        (state, "oculto"): Rule(_SUPERVISOR)
        for state in STATE_GROUPS
        if state != "oculto"
    },
}


def validate_transition(
    from_state: str,
    to_state: str,
    role: str,
    public_note: str | None = None,
    internal_note: str | None = None,
    previous_state: str | None = None,
) -> None:
    """Validate one change without mutating state or reading external resources."""
    rule = _RULES.get((from_state, to_state))
    if (
        from_state == "oculto"
        and to_state == previous_state
        and to_state in STATE_GROUPS
        and to_state != "oculto"
    ):
        rule = Rule(_SUPERVISOR)
    if rule is None:
        raise InvalidTransition("Illegal case transition")
    if ("supervisor" if role == "admin" else role) not in rule.roles:
        raise RoleForbidden("Insufficient role for case transition")
    has_public = bool(public_note and public_note.strip())
    has_internal = bool(internal_note and internal_note.strip())
    if rule.internal_required and not has_internal:
        raise InvalidTransition("An internal explanation is required")
    if rule.note_required and not (has_public or has_internal):
        raise InvalidTransition("An explanation is required")


def resolution_for(state: str) -> str:
    return {
        "pending": "open",
        "open": "open",
        "in_work": "acknowledged",
        "resolved": "fixed",
        "closed": "closed",
        "hidden": "closed",
    }[STATE_GROUPS[state]]
