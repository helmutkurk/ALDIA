import math

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Report

EARTH_RADIUS_METRES = 6371008.8


def hamming_distance(first: str, second: str) -> int:
    return (int(first, 16) ^ int(second, 16)).bit_count()


def distance_metres(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    dlat, dlon = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    return EARTH_RADIUS_METRES * 2 * math.asin(math.sqrt(min(1.0, max(0.0, a))))


def is_duplicate(
    session: Session, category: str, latitude: float, longitude: float, phash: str
) -> bool:
    # Latitude prefilter is safe at poles and across the antimeridian. Final
    # Haversine distance is authoritative; use a spatial index at higher volumes.
    delta = math.degrees(50 / EARTH_RADIUS_METRES)
    candidates = session.scalars(
        select(Report).where(
            Report.category == category,
            Report.phash.is_not(None),
            Report.latitude.between(latitude - delta, latitude + delta),
        )
    )
    return any(
        candidate.phash is not None
        and hamming_distance(candidate.phash, phash) <= 4
        and distance_metres(
            latitude, longitude, candidate.latitude, candidate.longitude
        )
        <= 50
        for candidate in candidates
    )
