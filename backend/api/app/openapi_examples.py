"""Synthetic OpenAPI response examples; no runtime request handling."""

from app.categories import CATEGORIES

DEMO_ID = "8d231ed0-b858-4bd5-bf2e-c8c5a4d2dd01"
AT = "2026-11-20T12:00:00Z"
CHECKS = [
    {
        "name": "image",
        "passed": True,
        "detail": "800x600 jpeg",
        "code": "image_ok",
    },
    {
        "name": "place",
        "passed": True,
        "detail": "Dentro de Guatemala.",
        "code": "place_ok",
    },
    {
        "name": "freshness",
        "passed": True,
        "detail": "Captura reciente.",
        "code": "freshness_ok",
    },
    {
        "name": "category",
        "passed": True,
        "detail": "no clasificado (sin modelo)",
        "code": "category_stub",
    },
    {"name": "duplicate", "passed": True, "detail": "no nearby duplicate"},
]
VERIFICATION = {"passed": True, "mode": "heuristic", "checks": CHECKS}
EVENTS = [
    {
        "at": AT,
        "actor": "system",
        "actor_role": "system",
        "from_state": "pendiente_verificacion",
        "to_state": "nuevo",
        "public_note": None,
    }
]
REPORT: dict[str, object] = {
    "id": DEMO_ID,
    "category": "pothole",
    "latitude": 14.6349,
    "longitude": -90.5069,
    "captured_at": AT,
    "created_at": AT,
    "status": "verified",
    "resolution": "open",
    "note": "[demo] Bache junto al cruce peatonal.",
    "photo_url": f"/api/reports/{DEMO_ID}/photo",
    "verification": VERIFICATION,
    "state": "nuevo",
    "state_group": "open",
    "state_changed_at": AT,
    "verified_at": AT,
    "resolved_at": None,
    "closed_at": None,
    "assignee": None,
    "assigned_at": None,
    "duplicate_of": None,
    "public_note": None,
    "events": EVENTS,
}
PAGE = {"items": [REPORT], "total": 1, "limit": 100, "offset": 0}
USER = {
    "id": DEMO_ID,
    "username": "operador_demo",
    "role": "operator",
    "disabled": False,
}
IDENTITY = {"user": {"username": "operador_demo", "role": "operator"}}
CATEGORY_ROWS = [
    {
        "category": code,
        "total": 0,
        "resueltos": 0,
        "abiertos": 0,
        "cerrados": 0,
        "mediana_reparacion_horas": None,
        "p90_reparacion_horas": None,
        "n_resueltos": 0,
    }
    for code, _ in CATEGORIES
]
EMPTY_STATS = {
    "total": 0,
    "by_category": {code: 0 for code, _ in CATEGORIES},
    "by_status": {"pending": 0, "verified": 0, "rejected": 0},
    "by_resolution": {"open": 0, "acknowledged": 0, "fixed": 0, "closed": 0},
    "recibidos": 0,
    "rechazados_verificador": 0,
    "abiertos": 0,
    "resueltos": 0,
    "cerrados_sin_solucion": 0,
    "tasa_resolucion": None,
    "tasa_resolucion_n": 0,
    "resolucion_horas": {"median": None, "p90": None, "mean": None, "n": 0},
    "primera_respuesta_horas": {"median": None, "p90": None, "n": 0},
    "antiguedad_abiertos": {"0-2": 0, "3-7": 0, "8-30": 0, ">30": 0},
    "sla_cumplido": None,
    "vencidos": 0,
    "by_state": {},
    "by_state_group": {},
    "weekly": [],
    "por_categoria": CATEGORY_ROWS,
    "top_categorias": [],
}
