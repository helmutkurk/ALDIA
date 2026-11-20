"""Normalize untrusted Pillow EXIF values before checks evaluate their policy."""

import re
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta, timezone
from enum import Enum, auto
from math import isfinite
from typing import SupportsFloat, SupportsIndex

from PIL import Image

# Malformed present metadata is a failed check, never treated as absent.
EXIF_ERRORS = (
    ValueError,
    TypeError,
    KeyError,
    IndexError,
    OSError,
    OverflowError,
    ZeroDivisionError,
    AttributeError,
    SyntaxError,
)


class ExifState(Enum):
    MISSING = auto()
    INVALID = auto()


@dataclass(frozen=True)
class CaptureTime:
    captured_at: datetime
    has_offset: bool


@dataclass(frozen=True)
class Coordinates:
    latitude: float
    longitude: float


@dataclass(frozen=True)
class Metadata:
    time: CaptureTime | ExifState
    gps: Coordinates | ExifState


def read_ifd(exif: Image.Exif, tag: int) -> Mapping[int, object] | None:
    if tag not in exif:
        return {}
    try:
        # Resolve nested offsets while the source image is still open.
        return dict(exif.get_ifd(tag))
    except EXIF_ERRORS:
        return None


def capture_time(tags: Mapping[int, object] | None) -> CaptureTime | ExifState:
    if tags is not None and 36867 not in tags:
        return ExifState.MISSING
    try:
        if tags is None or not isinstance(tags[36867], str):
            raise ValueError("Invalid EXIF timestamp")
        timestamp = datetime.strptime(tags[36867], "%Y:%m:%d %H:%M:%S")
        zone = UTC
        has_offset = 36881 in tags
        if has_offset:
            offset = tags[36881]
            if not isinstance(offset, str) or not re.fullmatch(
                r"[+-]\d{2}:\d{2}", offset
            ):
                raise ValueError("Invalid EXIF offset")
            hours, minutes = int(offset[1:3]), int(offset[4:6])
            if hours > 23 or minutes > 59:
                raise ValueError("Invalid EXIF offset")
            delta = timedelta(hours=hours, minutes=minutes)
            zone = timezone(delta if offset[0] == "+" else -delta)
        return CaptureTime(timestamp.replace(tzinfo=zone), has_offset)
    except EXIF_ERRORS:
        return ExifState.INVALID


def coordinate(
    value: object, ref: object, positive: str, negative: str, limit: int
) -> float:
    if not isinstance(value, tuple | list) or len(value) != 3:
        raise ValueError("Invalid EXIF DMS")
    parts: tuple[object, ...] | list[object] = value
    numbers = []
    for part in parts:
        if not isinstance(
            part, str | bytes | bytearray | SupportsFloat | SupportsIndex
        ):
            raise ValueError("Invalid EXIF DMS component")
        numbers.append(float(part))
    degrees, minutes, seconds = numbers
    if (
        not all(isfinite(part) for part in numbers)
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


def gps_coordinates(tags: Mapping[int, object] | None) -> Coordinates | ExifState:
    if tags == {}:
        return ExifState.MISSING
    try:
        if tags is None:
            raise ValueError("Invalid GPS IFD")
        return Coordinates(
            coordinate(tags[2], tags[1], "N", "S", 90),
            coordinate(tags[4], tags[3], "E", "W", 180),
        )
    except EXIF_ERRORS:
        return ExifState.INVALID
