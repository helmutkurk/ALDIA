import warnings
from dataclasses import dataclass
from io import BytesIO
from typing import Any

from PIL import Image, ImageOps, UnidentifiedImageError

# Malformed present metadata is a failed check, never silently treated as absent.
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


@dataclass(frozen=True)
class Metadata:
    time: dict[int, Any] | None
    gps: dict[int, Any] | None


def read_ifd(exif: Image.Exif, tag: int) -> dict[int, Any] | None:
    if tag not in exif:
        return {}
    try:
        # Resolve nested offsets while the source image is still open.
        return dict(exif.get_ifd(tag))
    except EXIF_ERRORS:
        return None


def decode_image(data: bytes) -> tuple[Image.Image, Metadata]:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(data)) as image:
                if image.format not in {"JPEG", "PNG"}:
                    raise ValueError("Only JPEG and PNG images are supported")
                image.load()
                exif = image.getexif()
                metadata = Metadata(read_ifd(exif, 34665), read_ifd(exif, 34853))
                return ImageOps.exif_transpose(image).convert("RGB"), metadata
    except (
        UnidentifiedImageError,
        OSError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ) as exc:
        raise ValueError("Image could not be decoded safely") from exc


def grayscale(image: Image.Image, max_side: int) -> Image.Image:
    gray = image.convert("L")
    gray.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    return gray
