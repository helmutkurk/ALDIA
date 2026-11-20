"""All fixtures are generated with Pillow; no personal photos or model runtime."""

import random
from datetime import UTC, datetime, timedelta
from io import BytesIO

import pytest
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageFilter
from PIL.TiffImagePlugin import IFDRational

from app.checks import StubClassifier, VerifyInput, verify
from app.config import Settings
from app.main import create_app
from app.phash import dhash

NOW = datetime(2026, 11, 19, 12, 0, tzinfo=UTC)


def scene() -> Image.Image:
    image = Image.new("RGB", (640, 480), (128, 128, 128))
    draw = ImageDraw.Draw(image)
    rng = random.Random(42)
    for _ in range(240):
        x, y = rng.randrange(620), rng.randrange(460)
        shade = rng.randrange(32, 224)
        draw.rectangle((x, y, x + 20, y + 20), fill=(shade, shade, shade))
    return image


def encoded(image: Image.Image, exif: Image.Exif | None = None) -> bytes:
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=95, exif=exif or Image.Exif())
    return buffer.getvalue()


def result(
    image: Image.Image | None = None,
    exif: Image.Exif | None = None,
    settings: Settings | None = None,
    captured_at: datetime = NOW,
):
    return verify(
        encoded(image if image is not None else scene(), exif),
        VerifyInput(
            category="pothole",
            latitude=14.6349,
            longitude=-90.5069,
            captured_at=captured_at,
        ),
        StubClassifier(),
        settings or Settings(),
        now=NOW,
    )


def check(name: str, **kwargs):
    return next(c for c in result(**kwargs).checks if c.name == name)


def time_exif(timestamp: str, offset: str | None = None) -> Image.Exif:
    exif = Image.Exif()
    tags = {36867: timestamp}
    if offset is not None:
        tags[36881] = offset
    exif[34665] = tags
    return exif


def gps_exif(latitude: float = 14.6349, longitude: float = -90.5069) -> Image.Exif:
    def dms(value: float) -> tuple[IFDRational, IFDRational, IFDRational]:
        value = abs(value)
        degree = int(value)
        minutes = int((value - degree) * 60)
        seconds = (value - degree - minutes / 60) * 3600
        return IFDRational(degree), IFDRational(minutes), IFDRational(seconds)

    exif = Image.Exif()
    exif[34853] = {
        1: "N" if latitude >= 0 else "S",
        2: dms(latitude),
        3: "E" if longitude >= 0 else "W",
        4: dms(longitude),
    }
    return exif


def test_good_image_is_heuristic_with_named_codes_and_unchanged_hash() -> None:
    data = encoded(scene())
    verdict = result()
    assert verdict.passed
    assert verdict.mode == "heuristic"
    assert verdict.phash == dhash(Image.open(BytesIO(data)).convert("RGB"))
    assert {c.name for c in verdict.checks} == {
        "image",
        "place",
        "freshness",
        "sharpness",
        "exposure",
        "exif_time",
        "exif_gps",
        "screen_photo",
        "category",
    }
    assert all(c.code and c.detail for c in verdict.checks)
    assert verdict.checks[-1].detail == "no clasificado (sin modelo)"
    assert verdict.checks[-1].code == "category_stub"


def test_blur_rejects_and_sharpness_threshold_is_configurable() -> None:
    assert check("sharpness").passed
    blurry = scene().filter(ImageFilter.GaussianBlur(8))
    assert check("sharpness", image=blurry).code == "blurry"
    assert not result(image=blurry).passed
    assert not check("sharpness", settings=Settings(sharpness_min=1e9)).passed
    assert check("sharpness", image=blurry, settings=Settings(sharpness_min=0)).passed
    assert "varianza" in check("sharpness").detail


@pytest.mark.parametrize(("shade", "code"), [(0, "underexposed"), (255, "overexposed")])
def test_extreme_exposure_rejects(shade: int, code: str) -> None:
    image = Image.new("RGB", (640, 480), (shade, shade, shade))
    assert check("exposure", image=image).code == code
    assert not result(image=image).passed


def test_exposure_clipping_and_configuration() -> None:
    image = Image.new("L", (640, 480), 0)
    ImageDraw.Draw(image).rectangle((320, 0, 639, 479), fill=255)
    assert check("exposure", image=image).code == "exposure_clipped"
    assert (
        check("exposure", settings=Settings(exposure_min_mean=200)).code
        == "underexposed"
    )
    assert (
        check("exposure", settings=Settings(exposure_max_mean=60)).code == "overexposed"
    )
    assert not check("exposure", image=image).passed


@pytest.mark.parametrize("name", ["exif_time", "exif_gps"])
def test_absent_exif_is_explicitly_allowed(name: str) -> None:
    c = check(name)
    assert (c.passed, c.code, c.detail) == (True, "exif_missing", "sin EXIF")


@pytest.mark.parametrize(
    ("age", "passed"), [(-61, False), (-60, True), (600, True), (601, False)]
)
def test_exif_time_server_boundaries(age: int, passed: bool) -> None:
    captured = NOW - timedelta(seconds=age)
    c = check(
        "exif_time",
        exif=time_exif(captured.strftime("%Y:%m:%d %H:%M:%S")),
        captured_at=captured,
    )
    assert c.passed is passed
    assert c.code == ("exif_time_ok" if passed else "exif_time_outside")


@pytest.mark.parametrize(
    ("delta", "passed"), [(-121, False), (-120, True), (120, True), (121, False)]
)
def test_exif_time_app_consistency(delta: int, passed: bool) -> None:
    c = check(
        "exif_time",
        exif=time_exif("2026:11:19 12:00:00"),
        captured_at=NOW + timedelta(seconds=delta),
    )
    assert c.passed is passed


def test_exif_time_offset_and_configured_age() -> None:
    assert check("exif_time", exif=time_exif("2026:11:19 14:00:00", "+02:00")).passed
    assert check("exif_time", exif=time_exif("2026:11:19 06:00:00", "-06:00")).passed
    assert (
        check(
            "exif_time",
            exif=time_exif("2026:11:19 11:59:49"),
            settings=Settings(max_age_seconds=10),
        ).code
        == "exif_time_outside"
    )


@pytest.mark.parametrize(
    ("timestamp", "offset"),
    [
        ("nonsense", None),
        ("", None),
        ("2026:11:19 12:00:00", "+99:00"),
        ("2026:11:19 12:00:00", "oops"),
    ],
)
def test_malformed_present_time_fails(timestamp: str, offset: str | None) -> None:
    c = check("exif_time", exif=time_exif(timestamp, offset))
    assert not c.passed
    assert c.code == "exif_time_invalid"


@pytest.mark.parametrize(
    ("latitude", "passed"),
    [(14.6349, True), (14.6362, True), (14.6363, False), (14.65, False)],
)
def test_exif_gps_distance(latitude: float, passed: bool) -> None:
    c = check("exif_gps", exif=gps_exif(latitude))
    assert c.passed is passed
    assert c.code == ("exif_gps_ok" if passed else "exif_gps_mismatch")
    assert "distancia" in c.detail


def test_malformed_present_gps_fails() -> None:
    exif = Image.Exif()
    exif[34853] = {1: "N", 2: (IFDRational(14), IFDRational(90), IFDRational(0))}
    assert check("exif_gps", exif=exif).code == "exif_gps_invalid"
    assert not result(exif=exif).passed


def test_periodic_screen_hint_is_soft() -> None:
    image = scene()
    draw = ImageDraw.Draw(image)
    for x in range(0, 640, 40):
        draw.rectangle((x, 0, x + 19, 479), fill=(48, 48, 48))
        draw.rectangle((x + 20, 0, x + 39, 479), fill=(208, 208, 208))
    c = check("screen_photo", image=image)
    assert (c.passed, c.code) == (True, "possible_screen")
    assert result(image=image).passed
    assert check("screen_photo").code == "screen_clear"
    assert (
        check("screen_photo", image=Image.new("RGB", (640, 480), "gray")).code
        == "screen_clear"
    )


def test_http_rejects_blur_and_reports_missing_exif() -> None:
    with TestClient(create_app(Settings())) as client:
        response = client.post(
            "/verify",
            data={
                "category": "pothole",
                "latitude": "14.6349",
                "longitude": "-90.5069",
                "captured_at": datetime.now(UTC).isoformat(),
            },
            files={
                "photo": (
                    "synthetic.jpg",
                    encoded(scene().filter(ImageFilter.GaussianBlur(8))),
                )
            },
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["mode"] == "heuristic"
        assert payload["passed"] is False
        assert (
            next(c for c in payload["checks"] if c["name"] == "sharpness")["code"]
            == "blurry"
        )
        assert client.get("/health").json()["mode"] == "heuristic"


def test_legacy_stub_config_still_runs_real_checks() -> None:
    assert result(settings=Settings(verifier_mode="stub")).mode == "heuristic"
    assert not result(
        image=scene().filter(ImageFilter.GaussianBlur(8)),
        settings=Settings(verifier_mode="stub"),
    ).passed
