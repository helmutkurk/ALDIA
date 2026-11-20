from app.checks.context import CheckContext
from app.schemas import Check


def run(context: CheckContext) -> Check:
    width, height = context.image.size
    passed = width >= 640 and height >= 480
    return Check(
        name="image",
        passed=passed,
        detail=f"{width}x{height}; mínimo 640x480",
        code="image_ok" if passed else "image_too_small",
    )
