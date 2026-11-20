from math import sqrt

from app.checks.context import CheckContext
from app.imaging import grayscale
from app.schemas import Check


def periodic_peak(profile: list[float]) -> float:
    # Second differences remove constant/linear illumination gradients.
    values = [
        profile[i - 1] - 2 * profile[i] + profile[i + 1]
        for i in range(1, len(profile) - 1)
    ]
    if len(values) < 20 or sum(v * v for v in values) / len(values) < 16:
        return 0.0
    correlations = [0.0]
    for lag in range(1, min(18, len(values) // 2)):
        left, right = values[:-lag], values[lag:]
        energy = sqrt(sum(v * v for v in left) * sum(v * v for v in right))
        correlations.append(
            sum(a * b for a, b in zip(left, right, strict=True)) / energy
            if energy
            else 0.0
        )
    # A peak must rise above both neighbors, not just broad spatial correlation.
    return max(
        (
            correlations[i]
            for i in range(2, len(correlations) - 1)
            if correlations[i] - max(correlations[i - 1], correlations[i + 1]) >= 0.2
        ),
        default=0.0,
    )


def run(context: CheckContext) -> Check:
    gray = grayscale(context.image, 128)
    width, height = gray.size
    pixels = gray.tobytes()
    rows = [sum(pixels[y * width : (y + 1) * width]) / width for y in range(height)]
    columns = [sum(pixels[x::width]) / height for x in range(width)]
    peak = max(periodic_peak(rows), periodic_peak(columns))
    suspicious = peak >= context.settings.screen_min_correlation
    detail = (
        "posible foto de pantalla: patrón periódico "
        f"(correlación {peak:.3f}); revisión manual sugerida"
        if suspicious
        else "sin patrón periódico significativo"
    )
    return Check(
        name="screen_photo",
        passed=True,
        detail=detail,
        code="possible_screen" if suspicious else "screen_clear",
    )
