from fastapi import APIRouter, Response
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.categories import CATEGORIES, CATEGORY_GROUPS, SLA_HOURS
from app.dependencies import ServicesDep

router = APIRouter(prefix="/api")


@router.get("/health")
def health(services: ServicesDep, response: Response) -> dict[str, object]:
    dependencies = {"database": "ok", "verifier": "ok", "photos": "ok"}
    try:
        with services.database.engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except SQLAlchemyError:
        dependencies["database"] = "unavailable"
    if not services.verifier.healthy():
        dependencies["verifier"] = "unavailable"
    try:
        services.storage.probe()
    except OSError:
        dependencies["photos"] = "unavailable"
    healthy = all(value == "ok" for value in dependencies.values())
    response.status_code = 200 if healthy else 503
    response.headers["Cache-Control"] = "no-store"
    return {"status": "ok" if healthy else "degraded", "dependencies": dependencies}


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
