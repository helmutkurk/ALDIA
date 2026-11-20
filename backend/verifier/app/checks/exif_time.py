from app.checks.context import CheckContext
from app.metadata import ExifState
from app.schemas import Check


def run(context: CheckContext) -> Check:
    timestamp = context.metadata.time
    if isinstance(timestamp, ExifState):
        missing = timestamp is ExifState.MISSING
        return Check(
            name="exif_time",
            passed=missing,
            detail="sin EXIF" if missing else "fecha EXIF inválida",
            code="exif_missing" if missing else "exif_time_invalid",
        )
    captured = timestamp.captured_at
    age = (context.now - captured).total_seconds()
    difference = abs((context.report.captured_at - captured).total_seconds())
    assumption = (
        "; zona EXIF aplicada"
        if timestamp.has_offset
        else "; sin zona EXIF, se asume UTC"
    )
    code = "exif_time_ok"
    if not -60 <= age <= context.settings.max_age_seconds:
        code = "exif_time_outside"
    elif difference > 120:
        code = "exif_time_mismatch"
    return Check(
        name="exif_time",
        passed=code == "exif_time_ok",
        code=code,
        detail=(
            f"antigüedad EXIF {age:.0f} s; diferencia {difference:.0f} s{assumption}"
        ),
    )
