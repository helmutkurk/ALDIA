from app.checks.context import CheckContext
from app.schemas import Check


def run(context: CheckContext) -> Check:
    histogram = context.gray.histogram()
    count = sum(histogram)
    mean = sum(value * n for value, n in enumerate(histogram)) / count
    clipped = (sum(histogram[:6]) + sum(histogram[250:])) / count
    config = context.settings
    code = "exposure_ok"
    if mean < config.exposure_min_mean:
        code = "underexposed"
    elif mean > config.exposure_max_mean:
        code = "overexposed"
    elif clipped > config.exposure_max_clipped_ratio:
        code = "exposure_clipped"
    return Check(
        name="exposure",
        passed=code == "exposure_ok",
        code=code,
        detail=f"luminancia media {mean:.2f}; píxeles recortados {clipped:.4f}",
    )
