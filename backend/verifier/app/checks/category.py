from typing import Protocol

from PIL import Image

from app.schemas import Check


class Classifier(Protocol):
    def classify(self, image: Image.Image, category: str) -> Check:
        """Return the category check for a decoded image."""
        ...


class StubClassifier:
    def classify(self, image: Image.Image, category: str) -> Check:
        return Check(
            name="category",
            passed=True,
            detail="no clasificado (sin modelo)",
            code="category_stub",
        )
