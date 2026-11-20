from app.checks.context import CheckContext
from app.schemas import Check


def run(context: CheckContext) -> Check:
    age = (context.now - context.report.captured_at).total_seconds()
    passed = -60 <= age <= context.settings.max_age_seconds
    return Check(
        name="freshness",
        passed=passed,
        detail=f"antigüedad {age:.0f} s",
        code="freshness_ok" if passed else "freshness_outside",
    )
