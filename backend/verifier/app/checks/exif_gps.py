from math import asin, cos, isfinite, radians, sin, sqrt
from typing import Any

from app.checks.context import CheckContext
from app.imaging import EXIF_ERRORS
from app.schemas import Check


def coordinate(value: Any, ref: Any, positive: str, negative: str, limit: int) -> float:
    if not isinstance(value, tuple | list) or len(value) != 3:
        raise ValueError("Invalid EXIF DMS")
    degrees, minutes, seconds = (float(part) for part in value)
    if (
        not all(isfinite(part) for part in (degrees, minutes, seconds))
        or not 0 <= degrees <= limit
        or not 0 <= minutes < 60
        or not 0 <= seconds < 60
        or ref not in (positive, negative)
    ):
        raise ValueError("Invalid EXIF coordinate")
    result = degrees + minutes / 60 + seconds / 3600
    if result > limit:
        raise ValueError("EXIF coordinate out of range")
    return result if ref == positive else -result


def haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    dlat, dlon = radians(lat2 - lat1), radians(lon2 - lon1)
    a = (
        sin(dlat / 2) ** 2
        + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    )
    return 2 * 6371000 * asin(sqrt(min(1.0, max(0.0, a))))


def run(context: CheckContext) -> Check:
    gps = context.metadata.gps
    if gps == {}:
        return Check(
            name="exif_gps", passed=True, detail="sin EXIF", code="exif_missing"
        )
    try:
        if gps is None:
            raise ValueError("Invalid GPS IFD")
        latitude = coordinate(gps[2], gps[1], "N", "S", 90)
        longitude = coordinate(gps[4], gps[3], "E", "W", 180)
        distance = haversine(
            latitude, longitude, context.report.latitude, context.report.longitude
        )
    except EXIF_ERRORS:
        return Check(
            name="exif_gps",
            passed=False,
            detail="GPS EXIF inválido",
            code="exif_gps_invalid",
        )
    passed = distance <= 150
    return Check(
        name="exif_gps",
        passed=passed,
        detail=f"distancia EXIF {distance:.1f} m; máximo 150 m",
        code="exif_gps_ok" if passed else "exif_gps_mismatch",
    )
