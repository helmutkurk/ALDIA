from math import asin, cos, radians, sin, sqrt

from app.checks.context import CheckContext
from app.metadata import ExifState
from app.schemas import Check


def haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    dlat, dlon = radians(lat2 - lat1), radians(lon2 - lon1)
    a = (
        sin(dlat / 2) ** 2
        + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    )
    return 2 * 6371000 * asin(sqrt(min(1.0, max(0.0, a))))


def run(context: CheckContext) -> Check:
    gps = context.metadata.gps
    if isinstance(gps, ExifState):
        missing = gps is ExifState.MISSING
        return Check(
            name="exif_gps",
            passed=missing,
            detail="sin EXIF" if missing else "GPS EXIF inválido",
            code="exif_missing" if missing else "exif_gps_invalid",
        )
    distance = haversine(
        gps.latitude, gps.longitude, context.report.latitude, context.report.longitude
    )
    passed = distance <= 150
    return Check(
        name="exif_gps",
        passed=passed,
        detail=f"distancia EXIF {distance:.1f} m; máximo 150 m",
        code="exif_gps_ok" if passed else "exif_gps_mismatch",
    )
