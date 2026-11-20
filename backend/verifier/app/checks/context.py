from dataclasses import dataclass
from datetime import datetime

from PIL import Image

from app.config import Settings
from app.metadata import Metadata
from app.schemas import VerifyInput


@dataclass(frozen=True)
class CheckContext:
    image: Image.Image
    gray: Image.Image
    metadata: Metadata
    report: VerifyInput
    settings: Settings
    now: datetime
