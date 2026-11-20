from app.checks.context import CheckContext
from app.schemas import Check

# Broad MVP envelopes (min longitude, min latitude, max longitude, max latitude).
# These intentionally include offshore areas; they are not country polygons.
COUNTRY_BOUNDS = {
    "GT": (-92.3, 13.7, -88.2, 17.9),
    "CO": (-81.8, -4.3, -66.8, 13.6),
    "MX": (-118.5, 14.5, -86.7, 32.8),
}


def run(context: CheckContext) -> Check:
    country = next(
        (
            name
            for name, (west, south, east, north) in COUNTRY_BOUNDS.items()
            if west <= context.report.longitude <= east
            and south <= context.report.latitude <= north
        ),
        None,
    )
    return Check(
        name="place",
        passed=country is not None,
        detail=f"inside {country}" if country else "fuera de las zonas admitidas",
        code="place_ok" if country else "place_outside",
    )
