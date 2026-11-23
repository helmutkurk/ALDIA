"""Provider-neutral interface for image/text embeddings in one shared space."""

import math
from collections.abc import Sequence
from typing import Protocol

Vector = list[float]


class EmbeddingUnavailable(RuntimeError):
    """The provider could not be reached or answered unusably.

    Messages stay generic: never include keys, URLs, photos or response bodies.
    """


class Embedder(Protocol):
    name: str

    def embed_image(self, jpeg: bytes) -> Vector:
        """Embed one JPEG image."""
        ...

    def embed_text(self, text: str) -> Vector:
        """Embed one short text in the same space as the images."""
        ...


def normalized(vector: Sequence[float]) -> Vector:
    length = math.sqrt(sum(value * value for value in vector))
    if not vector or length == 0 or not math.isfinite(length):
        raise EmbeddingUnavailable("Embedding provider returned an unusable vector")
    return [value / length for value in vector]


def cosine(left: Sequence[float], right: Sequence[float]) -> float:
    """Cosine similarity of two already normalized vectors."""
    if len(left) != len(right):
        raise EmbeddingUnavailable("Embedding dimensions do not match")
    return sum(a * b for a, b in zip(left, right, strict=True))


def float_vector(value: object) -> Vector:
    if not isinstance(value, list) or not value:
        raise EmbeddingUnavailable("Embedding provider returned no vector")
    if not all(
        isinstance(item, int | float) and not isinstance(item, bool) for item in value
    ):
        raise EmbeddingUnavailable("Embedding provider returned a non-numeric vector")
    try:
        vector = [float(item) for item in value]
    except OverflowError as exc:
        raise EmbeddingUnavailable("Embedding provider returned a huge number") from exc
    if not all(math.isfinite(item) for item in vector):
        raise EmbeddingUnavailable("Embedding provider returned a non-finite vector")
    return vector
