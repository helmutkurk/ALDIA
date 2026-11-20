from app.checks.context import CheckContext
from app.schemas import Check


def run(context: CheckContext) -> Check:
    width, height = context.gray.size
    pixels = context.gray.tobytes()
    total = total_squared = count = 0
    # Signed responses avoid Pillow's 8-bit filter clipping of negative edges.
    for y in range(1, height - 1):
        for x in range(1, width - 1):
            i = y * width + x
            edge = (
                4 * pixels[i]
                - pixels[i - 1]
                - pixels[i + 1]
                - pixels[i - width]
                - pixels[i + width]
            )
            total += edge
            total_squared += edge * edge
            count += 1
    variance = max(0.0, total_squared / count - (total / count) ** 2) if count else 0.0
    minimum = context.settings.sharpness_min
    passed = variance >= minimum
    return Check(
        name="sharpness",
        passed=passed,
        detail=f"varianza laplaciana {variance:.2f}; mínimo {minimum:.2f}",
        code="sharpness_ok" if passed else "blurry",
    )
