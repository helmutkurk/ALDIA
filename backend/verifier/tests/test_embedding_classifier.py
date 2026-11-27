"""EmbeddingClassifier ranking, prompt caching and the JPEG sent to providers."""

import threading
import time
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO

import pytest
from PIL import Image
from test_embeddings import axis, text_vector

from app.checks.category_prompts import LABELS, NO_PROBLEM, PROMPTS
from app.checks.embedding_classifier import MAX_SIDE, EmbeddingClassifier, provider_jpeg
from app.embeddings.base import EmbeddingUnavailable, Vector, normalized
from app.schemas import CATEGORIES

PROMPT_COUNT = sum(len(texts) for texts in PROMPTS.values())


class CountingEmbedder:
    """In-memory embedder: texts land on their label's axis, images on `image`."""

    name = "fake"

    def __init__(
        self,
        image: dict[str, float] | None = None,
        *,
        fail_on_text_call: int | None = None,
        delay: float = 0.0,
    ) -> None:
        self.image = image or {"pothole": 1.0}
        self.fail_on_text_call = fail_on_text_call
        self.delay = delay
        self.text_calls = 0
        self.image_calls = 0
        self._lock = threading.Lock()

    def embed_text(self, text: str) -> Vector:
        with self._lock:
            self.text_calls += 1
            call = self.text_calls
        if self.delay:
            time.sleep(self.delay)
        if call == self.fail_on_text_call:
            raise EmbeddingUnavailable("fake outage")
        return text_vector(text)

    def embed_image(self, jpeg: bytes) -> Vector:
        with self._lock:
            self.image_calls += 1
        return normalized(axis(self.image))


def classifier(top_k: int = 1, min_similarity: float = 0.0) -> EmbeddingClassifier:
    return EmbeddingClassifier(
        CountingEmbedder(), top_k=top_k, min_similarity=min_similarity
    )


def all_scores(**scores: float) -> dict[str, float]:
    """Scores for every label; unspecified labels score 0."""
    return {label: scores.get(label, 0.0) for label in PROMPTS}


def sample_image() -> Image.Image:
    return Image.new("RGB", (64, 48), "gray")


# Fixed ranking used for top_k boundaries; NO_PROBLEM ranks last.
RANKING = ["pothole", "sidewalk", "graffiti", "open_drain", "street_light"]
RANKING += ["accessibility", NO_PROBLEM]
RANKED_SCORES = {label: 0.9 - 0.1 * rank for rank, label in enumerate(RANKING)}


@pytest.mark.parametrize("top_k", range(1, 8))
@pytest.mark.parametrize("category", CATEGORIES)
def test_top_k_accepts_exactly_the_first_k_labels(top_k: int, category: str) -> None:
    check = classifier(top_k=top_k).decide(RANKED_SCORES, category)
    if RANKING.index(category) < top_k:
        assert check.passed and check.code == "category_match"
    else:
        assert not check.passed and check.code == "category_mismatch"
        assert check.detail == f"la foto parece mostrar: {LABELS['pothole']}"


def test_equal_scores_rank_alphabetically_by_label() -> None:
    scores = all_scores(pothole=0.5, sidewalk=0.5)
    decide = classifier(top_k=1).decide
    assert decide(scores, "pothole").code == "category_match"
    mismatch = decide(scores, "sidewalk")
    assert mismatch.code == "category_mismatch"
    assert mismatch.detail == "la foto parece mostrar: Bache"


def test_tie_breaking_does_not_depend_on_dict_order() -> None:
    forward = {"pothole": 0.5, "graffiti": 0.5, NO_PROBLEM: 0.1}
    backward = dict(reversed(list(forward.items())))
    decide = classifier(top_k=1).decide
    for scores in (forward, backward):
        assert decide(all_scores(**scores), "graffiti").code == "category_match"
        assert decide(all_scores(**scores), "pothole").code == "category_mismatch"


def test_no_problem_wins_ties_against_labels_sorting_after_it() -> None:
    # "ninguno" sorts before "pothole" but after "graffiti".
    decide = classifier(top_k=1).decide
    assert (
        decide(all_scores(pothole=0.5, **{NO_PROBLEM: 0.5}), "pothole").code
        == "category_no_problem"
    )
    assert (
        decide(all_scores(graffiti=0.5, **{NO_PROBLEM: 0.5}), "graffiti").code
        == "category_match"
    )


def test_no_problem_counts_as_a_competitor_for_top_k() -> None:
    scores = all_scores(pothole=0.7, sidewalk=0.6, **{NO_PROBLEM: 0.8})
    assert classifier(top_k=1).decide(scores, "pothole").code == "category_no_problem"
    assert classifier(top_k=2).decide(scores, "pothole").code == "category_match"
    assert classifier(top_k=2).decide(scores, "sidewalk").code == "category_no_problem"


def test_top_k_seven_accepts_every_category_even_on_a_no_problem_photo() -> None:
    scores = all_scores(**{NO_PROBLEM: 0.9})
    for category in CATEGORIES:
        assert classifier(top_k=7).decide(scores, category).code == "category_match"


def test_min_similarity_is_inclusive() -> None:
    scores = all_scores(pothole=0.3)
    check = classifier(min_similarity=0.3).decide(scores, "pothole")
    assert check.code == "category_match"
    assert check.detail == "coincide con la categoría (similitud 0.30)"


def test_score_just_below_min_similarity_is_low_similarity() -> None:
    check = classifier(min_similarity=0.3).decide(all_scores(pothole=0.2999), "pothole")
    assert not check.passed
    assert check.code == "category_low_similarity"
    assert check.detail == "similitud insuficiente con la categoría (0.30)"


def test_no_problem_takes_precedence_over_low_similarity() -> None:
    scores = all_scores(pothole=0.2, **{NO_PROBLEM: 0.4})
    check = classifier(top_k=2, min_similarity=0.3).decide(scores, "pothole")
    assert check.code == "category_no_problem"


def test_negative_min_similarity_accepts_negative_scores() -> None:
    scores = {label: -0.5 for label in PROMPTS} | {"pothole": -0.2}
    assert classifier(min_similarity=-1).decide(scores, "pothole").code == (
        "category_match"
    )


def test_scores_take_the_best_prompt_per_label() -> None:
    class SplitEmbedder(CountingEmbedder):
        def embed_text(self, text: str) -> Vector:
            # Only the English pothole prompt points straight at the image.
            if text == PROMPTS["pothole"][-1]:
                return normalized([1.0, 0.0])
            return normalized([0.0, 1.0])

        def embed_image(self, jpeg: bytes) -> Vector:
            return normalized([1.0, 0.0])

    scores = EmbeddingClassifier(SplitEmbedder()).scores(sample_image())
    assert set(scores) == set(PROMPTS)
    assert scores["pothole"] == pytest.approx(1.0)
    assert all(
        scores[label] == pytest.approx(0.0) for label in PROMPTS if label != "pothole"
    )


def test_prompts_are_embedded_once_across_many_classifications() -> None:
    embedder = CountingEmbedder()
    model = EmbeddingClassifier(embedder)
    model.warm_up()
    model.warm_up()
    for _ in range(25):
        assert model.classify(sample_image(), "pothole").code == "category_match"
    assert embedder.text_calls == PROMPT_COUNT
    assert embedder.image_calls == 25


def test_concurrent_first_calls_embed_the_prompts_once() -> None:
    embedder = CountingEmbedder(delay=0.001)
    model = EmbeddingClassifier(embedder)
    start = threading.Barrier(16)

    def run(_index: int) -> str:
        start.wait()
        return model.classify(sample_image(), "pothole").code

    with ThreadPoolExecutor(max_workers=16) as pool:
        codes = list(pool.map(run, range(16)))
    assert codes == ["category_match"] * 16
    assert embedder.text_calls == PROMPT_COUNT
    assert embedder.image_calls == 16


def test_failed_warm_up_caches_nothing_and_is_retried() -> None:
    embedder = CountingEmbedder(fail_on_text_call=3)
    model = EmbeddingClassifier(embedder)
    with pytest.raises(EmbeddingUnavailable):
        model.warm_up()
    assert embedder.text_calls == 3
    # The next request retries the whole set instead of using partial prompts.
    assert model.classify(sample_image(), "pothole").code == "category_match"
    assert embedder.text_calls == 3 + PROMPT_COUNT


def test_classifier_stores_its_thresholds() -> None:
    model = EmbeddingClassifier(CountingEmbedder(), top_k=7, min_similarity=-1)
    assert (model.top_k, model.min_similarity) == (7, -1)
    with pytest.raises(ValueError, match="top_k"):
        EmbeddingClassifier(CountingEmbedder(), top_k=-3)


def decode(jpeg: bytes) -> Image.Image:
    sent = Image.open(BytesIO(jpeg))
    sent.load()
    return sent


@pytest.mark.parametrize(
    ("mode", "color"),
    [
        ("RGBA", (200, 10, 10, 0)),
        ("RGBA", (200, 10, 10, 255)),
        ("LA", (90, 128)),
        ("L", 90),
        ("1", 1),
        ("P", 3),
        ("CMYK", (0, 255, 255, 0)),
        ("I", 1000),
        ("F", 12.5),
    ],
)
def test_provider_jpeg_accepts_any_pillow_mode(mode: str, color: object) -> None:
    image = Image.new(mode, (900, 300), color)  # type: ignore[arg-type]
    sent = decode(provider_jpeg(image))
    assert sent.format == "JPEG"
    assert sent.mode == "RGB"
    assert sent.size == (MAX_SIDE, 171)


def test_provider_jpeg_keeps_the_color_of_transparent_pixels_without_alpha() -> None:
    sent = decode(provider_jpeg(Image.new("RGBA", (40, 40), (200, 10, 10, 0))))
    red, green, blue = sent.getpixel((20, 20))  # type: ignore[misc]
    assert red > 150 and green < 60 and blue < 60


def test_provider_jpeg_does_not_upscale_small_images() -> None:
    assert decode(provider_jpeg(Image.new("RGB", (100, 50), "white"))).size == (100, 50)


def test_provider_jpeg_scales_the_longer_side_of_portrait_images() -> None:
    assert decode(provider_jpeg(Image.new("RGB", (600, 1200), "white"))).size == (
        256,
        512,
    )


def test_provider_jpeg_drops_exif_and_does_not_change_the_input() -> None:
    image = Image.new("RGB", (800, 600), "blue")
    exif = Image.Exif()
    exif[0x010F] = "SecretCam"  # Make
    exif[0x0112] = 6  # Orientation
    buffer = BytesIO()
    image.save(buffer, format="JPEG", exif=exif)
    original = Image.open(BytesIO(buffer.getvalue()))
    jpeg = provider_jpeg(original)
    assert b"SecretCam" not in jpeg
    assert not decode(jpeg).getexif()
    assert original.size == (800, 600)
