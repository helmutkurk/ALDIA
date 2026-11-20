import re
from datetime import UTC, datetime, timedelta, timezone

from app.checks.context import CheckContext
from app.imaging import EXIF_ERRORS
from app.schemas import Check


def run(context: CheckContext) -> Check:
    tags = context.metadata.time
    if tags is not None and 36867 not in tags:
        return Check(
            name="exif_time", passed=True, detail="sin EXIF", code="exif_missing"
        )
    try:
        if tags is None:
            raise ValueError("Invalid EXIF IFD")
        timestamp = datetime.strptime(tags[36867], "%Y:%m:%d %H:%M:%S")
        zone = UTC
        assumption = "; sin zona EXIF, se asume UTC"
        if 36881 in tags:
            offset = tags[36881]
            if not isinstance(offset, str) or not re.fullmatch(
                r"[+-]\d{2}:\d{2}", offset
            ):
                raise ValueError("Invalid EXIF offset")
            hours, minutes = int(offset[1:3]), int(offset[4:6])
            if hours > 23 or minutes > 59:
                raise ValueError("Invalid EXIF offset")
            delta = timedelta(hours=hours, minutes=minutes)
            zone = timezone(delta if offset[0] == "+" else -delta)
            assumption = "; zona EXIF aplicada"
        captured = timestamp.replace(tzinfo=zone)
        age = (context.now - captured).total_seconds()
        difference = abs((context.report.captured_at - captured).total_seconds())
    except EXIF_ERRORS:
        return Check(
            name="exif_time",
            passed=False,
            detail="fecha EXIF inválida",
            code="exif_time_invalid",
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
