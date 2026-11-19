import os
import tempfile
import warnings
from io import BytesIO
from pathlib import Path
from uuid import UUID

from PIL import Image, ImageOps, UnidentifiedImageError


class PhotoStorage:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()

    def path(self, report_id: UUID | str) -> Path:
        try:
            validated = UUID(str(report_id))
        except ValueError as exc:
            raise ValueError("Photo ID must be a UUID") from exc
        return self.root / f"{validated}.jpg"

    def prepare(self, data: bytes) -> bytes:
        """Sniff, fully decode, orient, and re-encode without any source metadata."""
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(BytesIO(data)) as source:
                    if source.format not in {"JPEG", "PNG"}:
                        raise ValueError("Only JPEG and PNG images are supported")
                    source.load()
                    oriented = ImageOps.exif_transpose(source).convert("RGB")
                    clean = Image.new("RGB", oriented.size)
                    clean.paste(oriented)
                    output = BytesIO()
                    clean.save(output, format="JPEG", quality=90)
                    return output.getvalue()
        except (
            UnidentifiedImageError,
            OSError,
            Image.DecompressionBombError,
            Image.DecompressionBombWarning,
        ) as exc:
            raise ValueError("Image could not be decoded safely") from exc

    def save(self, report_id: UUID, data: bytes) -> None:
        target = self.path(report_id)
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary: str | None = None
        try:
            with tempfile.NamedTemporaryFile(dir=self.root, delete=False) as file:
                temporary = file.name
                file.write(data)
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary, target)
        finally:
            if temporary is not None:
                Path(temporary).unlink(missing_ok=True)

    def delete(self, report_id: UUID) -> None:
        self.path(report_id).unlink(missing_ok=True)
