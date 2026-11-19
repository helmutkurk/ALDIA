from fastapi import APIRouter

from app.categories import CATEGORIES, CATEGORY_GROUPS, SLA_HOURS

router = APIRouter(prefix="/api")


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/categories")
def categories() -> list[dict[str, str | int]]:
    return [
        {
            "id": category_id,
            "label": label,
            "sla_hours": SLA_HOURS[category_id],
            "group": CATEGORY_GROUPS[category_id],
        }
        for category_id, label in CATEGORIES
    ]
