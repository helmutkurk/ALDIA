import warnings
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

from app.metadata import Metadata, capture_time, gps_coordinates, read_ifd


def decode_image(data: bytes) -> tuple[Image.Image, Metadata]:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(data)) as image:
                if image.format not in {"JPEG", "PNG"}:
                    raise ValueError("Only JPEG and PNG images are supported")
                image.load()
                exif = image.getexif()
                metadata = Metadata(
                    capture_time(read_ifd(exif, 34665)),
                    gps_coordinates(read_ifd(exif, 34853)),
                )
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
