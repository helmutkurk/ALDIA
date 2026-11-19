from fastapi import APIRouter

from app.categories import CATEGORIES

router = APIRouter(prefix="/api")


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/categories")
def categories() -> list[dict[str, str]]:
    return [{"id": category_id, "label": label} for category_id, label in CATEGORIES]
