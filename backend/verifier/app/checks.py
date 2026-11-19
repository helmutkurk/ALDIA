import warnings
from datetime import UTC, datetime
from io import BytesIO
from typing import Annotated, Literal, Protocol

from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator

from app.phash import dhash

CATEGORIES = (
    "accessibility",
    "sidewalk",
    "pothole",
    "graffiti",
    "open_drain",
    "street_light",
)
# Broad MVP envelopes (min longitude, min latitude, max longitude, max latitude).
# These intentionally include offshore areas; they are not country polygons.
COUNTRY_BOUNDS = {
    "GT": (-92.3, 13.7, -88.2, 17.9),
    "CO": (-81.8, -4.3, -66.8, 13.6),
    "MX": (-118.5, 14.5, -86.7, 32.8),
}


class StrictModel(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", allow_inf_nan=False)


class VerifyInput(StrictModel):
    category: str
    latitude: Annotated[float, Field(ge=-90, le=90)]
    longitude: Annotated[float, Field(ge=-180, le=180)]
    captured_at: AwareDatetime

    @field_validator("category")
    @classmethod
    def supported_category(cls, value: str) -> str:
        if value not in CATEGORIES:
            raise ValueError("Unsupported category")
        return value


class Check(StrictModel):
    name: str
    passed: bool
    detail: str


class VerifyResult(StrictModel):
    passed: bool
    mode: Literal["stub", "model"]
    phash: Annotated[str, Field(pattern=r"^[0-9a-f]{16}$")]
    checks: list[Check]


class Classifier(Protocol):
    def classify(self, image: Image.Image, category: str) -> Check:
        """Return the category check for a decoded image."""
        ...


class StubClassifier:
    def classify(self, image: Image.Image, category: str) -> Check:
        return Check(name="category", passed=True, detail="stub: not classified")


def decode_image(data: bytes) -> Image.Image:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(data)) as image:
                if image.format not in {"JPEG", "PNG"}:
                    raise ValueError("Only JPEG and PNG images are supported")
                image.load()
                return ImageOps.exif_transpose(image).convert("RGB")
    except (
        UnidentifiedImageError,
        OSError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ) as exc:
        raise ValueError("Image could not be decoded safely") from exc


def verify(
    data: bytes,
    report: VerifyInput,
    classifier: Classifier,
    mode: Literal["stub", "model"],
    max_age_seconds: int,
    *,
    now: datetime | None = None,
) -> VerifyResult:
    image = decode_image(data)
    width, height = image.size
    image_check = Check(
        name="image",
        passed=width >= 640 and height >= 480,
        detail=f"{width}x{height} decoded image; minimum 640x480",
    )
    country = next(
        (
            name
            for name, (west, south, east, north) in COUNTRY_BOUNDS.items()
            if west <= report.longitude <= east and south <= report.latitude <= north
        ),
        None,
    )
    place = Check(
        name="place",
        passed=country is not None,
        detail=f"inside {country}" if country else "outside supported bounding boxes",
    )
    age = ((now or datetime.now(UTC)) - report.captured_at).total_seconds()
    freshness = Check(
        name="freshness",
        passed=-60 <= age <= max_age_seconds,
        detail=f"age {age:.0f} s",
    )
    checks = [
        image_check,
        place,
        freshness,
        classifier.classify(image, report.category),
    ]
    return VerifyResult(
        passed=all(check.passed for check in checks),
        mode=mode,
        phash=dhash(image),
        checks=checks,
    )
