from datetime import UTC, datetime, timedelta
from io import BytesIO

import pytest
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from app.config import Settings
from app.main import create_app
from app.phash import dhash


def photo(size: tuple[int, int] = (640, 480), fmt: str = "JPEG") -> bytes:
    buffer = BytesIO()
    image = Image.new("RGB", size, "orange")
    draw = ImageDraw.Draw(image)
    for x in range(0, size[0], 20):
        draw.line((x, 0, size[0] - x, size[1] - 1), fill="navy", width=4)
    image.save(buffer, format=fmt)
    return buffer.getvalue()


def fields(**overrides: str) -> dict[str, str]:
    return {
        "category": "pothole",
        "latitude": "14.6349",
        "longitude": "-90.5069",
        "captured_at": datetime.now(UTC).isoformat(),
        **overrides,
    }


@pytest.fixture
def client() -> TestClient:
    return TestClient(create_app(Settings()))


def test_health(client: TestClient) -> None:
    assert client.get("/health").json() == {"status": "ok", "mode": "heuristic"}


def test_verify_heuristic(client: TestClient) -> None:
    response = client.post(
        "/verify",
        data=fields(),
        files={"photo": ("ignored.txt", photo(), "text/plain")},
    )
    assert response.status_code == 200
    result = response.json()
    assert result["passed"] is True
    assert result["mode"] == "heuristic"
    assert len(result["phash"]) == 16
    assert {check["name"] for check in result["checks"]} == {
        "image",
        "place",
        "freshness",
        "category",
        "sharpness",
        "exposure",
        "exif_time",
        "exif_gps",
        "screen_photo",
    }
    assert result["checks"][-1]["detail"] == "no clasificado (sin modelo)"


@pytest.mark.parametrize(
    ("latitude", "longitude", "country"),
    [("14.6", "-90.5", "GT"), ("4.7", "-74.1", "CO"), ("19.4", "-99.1", "MX")],
)
def test_countries(
    client: TestClient, latitude: str, longitude: str, country: str
) -> None:
    result = client.post(
        "/verify",
        data=fields(latitude=latitude, longitude=longitude),
        files={"photo": ("photo.png", photo(fmt="PNG"))},
    ).json()
    assert result["passed"] is True
    assert result["checks"][1]["detail"] == f"inside {country}"


@pytest.mark.parametrize(
    ("overrides", "size", "failed_check"),
    [
        ({"latitude": "48.1", "longitude": "11.5"}, (640, 480), "place"),
        (
            {"captured_at": (datetime.now(UTC) - timedelta(seconds=601)).isoformat()},
            (640, 480),
            "freshness",
        ),
        (
            {"captured_at": (datetime.now(UTC) + timedelta(seconds=120)).isoformat()},
            (640, 480),
            "freshness",
        ),
        ({}, (639, 480), "image"),
        ({}, (640, 479), "image"),
    ],
)
def test_failed_checks(
    client: TestClient,
    overrides: dict[str, str],
    size: tuple[int, int],
    failed_check: str,
) -> None:
    result = client.post(
        "/verify", data=fields(**overrides), files={"photo": ("photo.jpg", photo(size))}
    ).json()
    assert result["passed"] is False
    assert (
        next(c for c in result["checks"] if c["name"] == failed_check)["passed"]
        is False
    )


@pytest.mark.parametrize(
    "overrides",
    [
        {"latitude": "nan"},
        {"longitude": "181"},
        {"captured_at": "2026-01-01"},
        {"category": "unknown"},
        {"extra": "no"},
    ],
)
def test_invalid_form(client: TestClient, overrides: dict[str, str]) -> None:
    response = client.post(
        "/verify", data=fields(**overrides), files={"photo": ("x", photo())}
    )
    assert response.status_code == 422
    assert set(response.json()) == {"error"}


@pytest.mark.parametrize("content", [b"not an image", photo(fmt="GIF"), photo()[:100]])
def test_invalid_image(client: TestClient, content: bytes) -> None:
    response = client.post(
        "/verify", data=fields(), files={"photo": ("x.jpg", content)}
    )
    assert response.status_code == 422


def test_model_mode_needs_a_provider_and_its_key() -> None:
    with pytest.raises(ValueError, match="EMBEDDING_PROVIDER"):
        Settings(verifier_mode="model")
    with pytest.raises(ValueError, match="GEMINI_API_KEY"):
        Settings(verifier_mode="model", embedding_provider="google")
    with pytest.raises(ValueError, match="AWS_BEARER_TOKEN_BEDROCK"):
        Settings(verifier_mode="model", embedding_provider="amazon")


def test_hash_is_64_bit_and_directional() -> None:
    image = Image.new("L", (9, 8))
    image.putdata([x * 28 for _y in range(8) for x in range(9)])
    assert dhash(image) == "0000000000000000"
    assert dhash(image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)) == "ffffffffffffffff"
    assert dhash(Image.new("RGB", (640, 480), "blue")) == "0000000000000000"


@pytest.mark.parametrize(
    ("age", "passed"), [(-61, False), (-60, True), (600, True), (601, False)]
)
def test_freshness_boundaries(age: int, passed: bool) -> None:
    from app.checks import StubClassifier, VerifyInput, verify

    now = datetime.now(UTC)
    report = VerifyInput(
        category="pothole",
        latitude=14.6,
        longitude=-90.5,
        captured_at=now - timedelta(seconds=age),
    )
    result = verify(photo(), report, StubClassifier(), Settings(), now=now)
    assert (
        next(check for check in result.checks if check.name == "freshness").passed
        is passed
    )


def test_missing_and_repeated_fields(client: TestClient) -> None:
    assert client.post("/verify", data=fields()).status_code == 422
    response = client.post(
        "/verify",
        data=fields(),
        files=[("photo", ("one.jpg", photo())), ("photo", ("two.jpg", photo()))],
    )
    assert response.status_code == 422


def test_configurable_max_age() -> None:
    with TestClient(create_app(Settings(max_age_seconds=10))) as client:
        result = client.post(
            "/verify",
            data=fields(
                captured_at=(datetime.now(UTC) - timedelta(seconds=20)).isoformat()
            ),
            files={"photo": ("x.jpg", photo())},
        ).json()
    assert result["passed"] is False


def test_body_limit(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.main as main_module

    monkeypatch.setattr(main_module, "MAX_IMAGE_BYTES", 100)
    with TestClient(create_app(Settings())) as test_client:
        response = test_client.post("/verify", content=b"x" * 70000)
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "upload_too_large"
