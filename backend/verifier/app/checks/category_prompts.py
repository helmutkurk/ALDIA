"""Texts that describe each category for zero-shot embedding comparison.

Spanish first (the app's language), one English line each because both models
are multilingual but saw more English. `NO_PROBLEM` describes photos that show
no street problem; if it ranks above the reported category, the check fails.
Change these texts only together with a new comparison run (training/).
"""

NO_PROBLEM = "ninguno"

LABELS: dict[str, str] = {
    "accessibility": "Accesibilidad (rampas, bordillos)",
    "sidewalk": "Acera en mal estado",
    "pothole": "Bache",
    "graffiti": "Grafiti",
    "open_drain": "Alcantarilla abierta",
    "street_light": "Luminaria dañada",
    NO_PROBLEM: "ningún problema urbano",
}

PROMPTS: dict[str, tuple[str, ...]] = {
    "accessibility": (
        "una foto de una rampa para sillas de ruedas rota o bloqueada en la acera",
        "una foto de un bordillo alto sin rampa en un cruce peatonal",
        "a photo of a broken or missing wheelchair ramp at a curb",
    ),
    "sidewalk": (
        "una foto de una acera rota con baldosas levantadas",
        "una foto de una banqueta agrietada y en mal estado",
        "a photo of a cracked and broken sidewalk",
    ),
    "pothole": (
        "una foto de un bache en la calle",
        "una foto de un hoyo grande en el asfalto de una carretera",
        "a photo of a pothole in an asphalt road",
    ),
    "graffiti": (
        "una foto de grafiti pintado en una pared",
        "una foto de pintas y vandalismo con aerosol en un muro",
        "a photo of graffiti spray painted on a wall",
    ),
    "open_drain": (
        "una foto de una alcantarilla abierta sin tapa en la calle",
        "una foto de un tragante o drenaje destapado en el suelo",
        "a photo of an open storm drain or manhole without a cover",
    ),
    "street_light": (
        "una foto de una lámpara de alumbrado público dañada",
        "una foto de un poste de luz roto o con la luminaria apagada",
        "a photo of a broken street light on a pole",
    ),
    NO_PROBLEM: (
        "una foto de una calle limpia y en buen estado",
        "una selfie o una foto de una persona",
        "una captura de pantalla de un teléfono o una computadora",
        "una foto de un interior, una habitación o una mesa",
        "una foto de una tapa de alcantarilla cerrada y en buen estado",
        "a photo of a closed manhole cover in good condition",
        "a photo of a well maintained street with no damage",
    ),
}
