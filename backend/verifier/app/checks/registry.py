from collections.abc import Callable
from datetime import UTC, datetime

from app.checks import (
    exif_gps,
    exif_time,
    exposure,
    freshness,
    image,
    place,
    screen_photo,
    sharpness,
)
from app.checks.category import Classifier
from app.checks.context import CheckContext
from app.config import Settings
from app.imaging import decode_image, grayscale
from app.phash import dhash
from app.schemas import Check, VerifyInput, VerifyResult

# Screen is soft: its implementation always returns passed=True.
HARD_CHECKS: tuple[Callable[[CheckContext], Check], ...] = (
    image.run,
    place.run,
    freshness.run,
    sharpness.run,
    exposure.run,
    exif_time.run,
    exif_gps.run,
)


def verify(
    data: bytes,
    report: VerifyInput,
    classifier: Classifier,
    settings: Settings,
    *,
    now: datetime | None = None,
) -> VerifyResult:
    if settings.verifier_mode == "model":
        raise NotImplementedError("VERIFIER_MODE=model requires a trained model")
    decoded, metadata = decode_image(data)
    context = CheckContext(
        decoded,
        grayscale(decoded, 320),
        metadata,
        report,
        settings,
        now or datetime.now(UTC),
    )
    hard = [check(context) for check in HARD_CHECKS]
    category = classifier.classify(decoded, report.category)
    return VerifyResult(
        passed=all(check.passed for check in [*hard, category]),
        mode="heuristic",
        phash=dhash(decoded),
        checks=[*hard, screen_photo.run(context), category],
    )
