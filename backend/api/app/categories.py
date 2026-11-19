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
