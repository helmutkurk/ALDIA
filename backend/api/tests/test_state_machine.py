from itertools import product

import pytest

from app.state_machine import (
    OPEN_STATES,
    STATE_GROUPS,
    InvalidTransition,
    RoleForbidden,
    resolution_for,
    validate_transition,
)

STATES = (
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
)
FLOW = ("nuevo", "en_revision", "programado", "en_proceso", "resuelto")
LEGAL = {
    ("pendiente_verificacion", "nuevo"),
    ("pendiente_verificacion", "rechazado_verificador"),
    ("rechazado_verificador", "nuevo"),
    ("en_revision", "no_procede"),
    ("en_revision", "fuera_de_competencia"),
    ("en_revision", "duplicado"),
    ("programado", "no_procede"),
    ("resuelto", "en_revision"),
    ("no_procede", "en_revision"),
    ("fuera_de_competencia", "en_revision"),
    ("duplicado", "en_revision"),
    *((a, b) for i, a in enumerate(FLOW) for b in FLOW[i + 1 :]),
    *((a, b) for i, a in enumerate(FLOW[:4]) for b in FLOW[:i]),
    *((state, "oculto") for state in STATES if state != "oculto"),
}


@pytest.mark.parametrize(("source", "target"), list(product(STATES, repeat=2)))
def test_every_state_pair(source: str, target: str) -> None:
    role = (
        "system"
        if source == "pendiente_verificacion" and target != "oculto"
        else "supervisor"
    )
    if (source, target) in LEGAL:
        validate_transition(source, target, role, internal_note="Reason")
    else:
        with pytest.raises(InvalidTransition):
            validate_transition(source, target, role, internal_note="Reason")


@pytest.mark.parametrize("previous", STATES[:-1])
def test_restore_only_previous(previous: str) -> None:
    validate_transition("oculto", previous, "supervisor", previous_state=previous)
    for other in STATES:
        if other != previous:
            with pytest.raises(InvalidTransition):
                validate_transition(
                    "oculto", other, "supervisor", previous_state=previous
                )


@pytest.mark.parametrize(("source", "target"), sorted(LEGAL))
def test_operator_permissions(source: str, target: str) -> None:
    privileged = (
        source
        in {
            "rechazado_verificador",
            "resuelto",
            "no_procede",
            "fuera_de_competencia",
            "duplicado",
        }
        or target == "oculto"
    )
    if source == "pendiente_verificacion" or privileged:
        with pytest.raises(RoleForbidden):
            validate_transition(source, target, "operator", internal_note="Reason")
    else:
        validate_transition(source, target, "operator", internal_note="Reason")


@pytest.mark.parametrize(("source", "target"), sorted(LEGAL))
def test_required_notes(source: str, target: str) -> None:
    skip = (
        source in FLOW
        and target in FLOW
        and FLOW.index(target) - FLOW.index(source) > 1
    )
    required = (
        skip
        or target in {"no_procede", "fuera_de_competencia"}
        or (
            target != "oculto"
            and source
            in {
                "rechazado_verificador",
                "no_procede",
                "fuera_de_competencia",
                "duplicado",
            }
        )
    )
    role = (
        "system"
        if source == "pendiente_verificacion" and target != "oculto"
        else "supervisor"
    )
    if required:
        for note in (None, "", "  \n"):
            with pytest.raises(InvalidTransition):
                validate_transition(
                    source, target, role, public_note=note, internal_note=note
                )
        if source != "rechazado_verificador":
            validate_transition(source, target, role, public_note="Public reason")
        else:
            with pytest.raises(InvalidTransition):
                validate_transition(source, target, role, public_note="Public only")
    else:
        validate_transition(source, target, role)


def test_unknown_states_and_roles() -> None:
    for source, target in (("bad", "nuevo"), ("nuevo", "bad")):
        with pytest.raises(InvalidTransition):
            validate_transition(source, target, "supervisor")
    with pytest.raises(RoleForbidden):
        validate_transition("nuevo", "en_revision", "viewer")
    with pytest.raises(RoleForbidden):
        validate_transition("nuevo", "en_revision", "system")
    with pytest.raises(RoleForbidden):
        validate_transition("oculto", "nuevo", "operator", previous_state="nuevo")


def test_groups_and_legacy_resolution() -> None:
    assert OPEN_STATES == ("nuevo", "en_revision", "programado", "en_proceso")
    assert set(STATE_GROUPS) == set(STATES)
    assert [resolution_for(s) for s in STATES] == [
        "open",
        "closed",
        "open",
        "open",
        "acknowledged",
        "acknowledged",
        "fixed",
        "closed",
        "closed",
        "closed",
        "closed",
    ]
