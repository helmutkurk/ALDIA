"""Contract category IDs and public labels; this is the API's single list."""

CATEGORIES = (
    ("accessibility", "Accesibilidad (rampas, bordillos)"),
    ("sidewalk", "Acera en mal estado"),
    ("pothole", "Bache"),
    ("graffiti", "Grafiti"),
    ("open_drain", "Alcantarilla abierta"),
    ("street_light", "Luminaria dañada"),
)
CATEGORY_IDS = frozenset(category_id for category_id, _label in CATEGORIES)


SLA_HOURS = {
    "accessibility": 720,
    "sidewalk": 720,
    "pothole": 240,
    "graffiti": 1440,
    "open_drain": 72,
    "street_light": 168,
}
CATEGORY_GROUPS = {
    "accessibility": "movilidad",
    "sidewalk": "movilidad",
    "pothole": "movilidad",
    "graffiti": "espacio_publico",
    "open_drain": "servicios",
    "street_light": "servicios",
}
