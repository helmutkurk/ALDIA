from collections.abc import Mapping
from datetime import UTC, datetime

import pytest
from PIL import Image
from PIL.TiffImagePlugin import IFDRational

from app.imaging import decode_image
from app.metadata import (
    CaptureTime,
    Coordinates,
    ExifState,
    capture_time,
    gps_coordinates,
)
from tests.test_heuristics import NOW, encoded, scene


@pytest.mark.parametrize(
    ("tags", "expected"),
    [
        ({}, ExifState.MISSING),
        ({36881: "invalid, but no timestamp"}, ExifState.MISSING),
        (None, ExifState.INVALID),
        ({36867: b"2026:11:19 12:00:00"}, ExifState.INVALID),
        ({36867: "2026:11:19 12:00:00", 36881: None}, ExifState.INVALID),
        (
            {36867: "2026:11:19 12:00:00"},
            CaptureTime(NOW, has_offset=False),
        ),
        (
            {36867: "2026:11:19 14:00:00", 36881: "+02:00"},
            CaptureTime(NOW, has_offset=True),
        ),
    ],
)
def test_time_normalization_preserves_presence_and_offsets(
    tags: Mapping[int, object] | None, expected: CaptureTime | ExifState
) -> None:
    assert capture_time(tags) == expected


@pytest.mark.parametrize(
    ("value", "reference", "expected"),
    [
        ((IFDRational(14), IFDRational(30), IFDRational(0)), "N", 14.5),
        ([14, 30, 0], "S", -14.5),
        (("14", "30", "0"), "N", 14.5),
        ((IFDRational(1, 0), 0, 0), "N", None),
        ((90, 0, 1), "N", None),
        ((14, 30), "N", None),
        ((14, object(), 0), "N", None),
        ((14, 30, 0), b"N", None),
    ],
)
def test_gps_normalization_preserves_numeric_and_invalid_values(
    value: object, reference: object, expected: float | None
) -> None:
    normalized = gps_coordinates({1: reference, 2: value, 3: "W", 4: (90, 0, 0)})
    assert normalized == (
        Coordinates(expected, -90) if expected is not None else ExifState.INVALID
    )


def test_gps_missing_and_incomplete_are_distinct() -> None:
    assert gps_coordinates({}) is ExifState.MISSING
    assert gps_coordinates(None) is ExifState.INVALID
    assert gps_coordinates({1: "N"}) is ExifState.INVALID


def test_unreadable_nested_ifds_remain_invalid(monkeypatch: pytest.MonkeyPatch) -> None:
    exif = Image.Exif()
    exif[34665] = {36867: "2026:11:19 12:00:00"}
    exif[34853] = {1: "N", 2: (14, 0, 0), 3: "W", 4: (90, 0, 0)}
    data = encoded(scene(), exif)

    def unreadable(_self: Image.Exif, _tag: int) -> dict[int, object]:
        raise ValueError("malformed nested IFD")

    monkeypatch.setattr(Image.Exif, "get_ifd", unreadable)
    _, metadata = decode_image(data)
    assert metadata.time is ExifState.INVALID
    assert metadata.gps is ExifState.INVALID


def test_normalized_values_survive_source_image_close() -> None:
    exif = Image.Exif()
    exif[34665] = {36867: "2026:11:19 12:00:00"}
    exif[34853] = {1: "S", 2: (14, 30, 0), 3: "E", 4: (90, 0, 0)}
    _, metadata = decode_image(encoded(scene(), exif))
    assert metadata.time == CaptureTime(datetime(2026, 11, 19, 12, tzinfo=UTC), False)
    assert metadata.gps == Coordinates(-14.5, 90)
