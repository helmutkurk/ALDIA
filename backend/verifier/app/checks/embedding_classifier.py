"""Zero-shot category check: compare the photo with texts per category.

Each label scores the best cosine similarity between the photo and its texts
(`category_prompts.py`). The check passes when the reported category ranks in
the top `top_k` labels (the "no problem" label counts as a competitor) and its
score reaches `min_similarity`. Both values need calibration per provider with
the comparison script in `training/`; the defaults are not calibrated.
"""

import io
import threading

from PIL import Image

from app.checks.category_prompts import LABELS, NO_PROBLEM, PROMPTS
from app.embeddings.base import Embedder, Vector, cosine
from app.schemas import Check

# Both providers downscale internally; 512 px keeps uploads small and private.
MAX_SIDE = 512


def provider_jpeg(image: Image.Image) -> bytes:
    """A small re-encoded JPEG without metadata, as sent to the provider."""
    copy = image.convert("RGB")
    copy.thumbnail((MAX_SIDE, MAX_SIDE))
    buffer = io.BytesIO()
    copy.save(buffer, format="JPEG", quality=85)
    return buffer.getvalue()


class EmbeddingClassifier:
    def __init__(
        self, embedder: Embedder, *, top_k: int = 1, min_similarity: float = 0.0
    ) -> None:
        if top_k < 1:
            raise ValueError("top_k must be at least 1")
        self.embedder = embedder
        self.top_k = top_k
        self.min_similarity = min_similarity
        self._prompts: dict[str, list[Vector]] | None = None
        self._lock = threading.Lock()

    def warm_up(self) -> None:
        """Embed all category texts once; raises EmbeddingUnavailable on failure."""
        with self._lock:
            if self._prompts is None:
                self._prompts = {
                    label: [self.embedder.embed_text(text) for text in texts]
                    for label, texts in PROMPTS.items()
                }

    def scores(self, image: Image.Image) -> dict[str, float]:
        self.warm_up()
        assert self._prompts is not None
        photo = self.embedder.embed_image(provider_jpeg(image))
        return {
            label: max(cosine(photo, vector) for vector in vectors)
            for label, vectors in self._prompts.items()
        }

    def classify(self, image: Image.Image, category: str) -> Check:
        return self.decide(self.scores(image), category)

    def decide(self, scores: dict[str, float], category: str) -> Check:
        """The category check for precomputed scores (reused by training/)."""
        ranking = sorted(scores, key=lambda label: (-scores[label], label))
        best = ranking[0]
        score = scores[category]
        if category in ranking[: self.top_k] and score >= self.min_similarity:
            return Check(
                name="category",
                passed=True,
                detail=f"coincide con la categoría (similitud {score:.2f})",
                code="category_match",
            )
        if best == NO_PROBLEM:
            return Check(
                name="category",
                passed=False,
                detail="la foto no parece mostrar un problema urbano",
                code="category_no_problem",
            )
        if category in ranking[: self.top_k]:
            return Check(
                name="category",
                passed=False,
                detail=f"similitud insuficiente con la categoría ({score:.2f})",
                code="category_low_similarity",
            )
        return Check(
            name="category",
            passed=False,
            detail=f"la foto parece mostrar: {LABELS[best]}",
            code="category_mismatch",
        )
