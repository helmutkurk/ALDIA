import math
from datetime import UTC, datetime, timedelta
from typing import Annotated, Literal, Self
from uuid import UUID

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from app.categories import CATEGORY_IDS

Status = Literal["pending", "verified", "rejected"]
Resolution = Literal["open", "acknowledged", "fixed"]


class StrictModel(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", allow_inf_nan=False)


def validate_category(value: str) -> str:
    if value not in CATEGORY_IDS:
        raise ValueError("Unsupported category")
    return value


class ReportCreate(StrictModel):
    category: str
    latitude: Annotated[float, Field(ge=-90, le=90)]
    longitude: Annotated[float, Field(ge=-180, le=180)]
    captured_at: AwareDatetime
    note: Annotated[str | None, Field(max_length=280)] = None

    _category = field_validator("category")(validate_category)

    @field_validator("captured_at")
    @classmethod
    def capture_time(cls, value: datetime) -> datetime:
        if value > datetime.now(UTC) + timedelta(seconds=60):
            raise ValueError("Capture time is too far in the future")
        return value.astimezone(UTC)


class Check(StrictModel):
    name: str
    passed: bool
    detail: str


class Verification(StrictModel):
    passed: bool
    mode: Literal["stub", "model"]
    checks: list[Check]


class VerifierResult(Verification):
    phash: Annotated[str, Field(pattern=r"^[0-9a-f]{16}$")]

    @model_validator(mode="after")
    def consistent_checks(self) -> Self:
        names = [check.name for check in self.checks]
        if set(names) != {"image", "place", "freshness", "category"} or len(names) != 4:
            raise ValueError("Verifier returned incomplete checks")
        if self.passed != all(check.passed for check in self.checks):
            raise ValueError("Verifier returned inconsistent checks")
        return self


class ReportOut(StrictModel):
    id: UUID
    category: str
    latitude: float
    longitude: float
    captured_at: AwareDatetime
    created_at: AwareDatetime
    status: Status
    resolution: Resolution
    note: str | None
    photo_url: str
    verification: Verification | None


class ReportList(StrictModel):
    items: list[ReportOut]
    total: int


class ReadFilters(StrictModel):
    bbox: str | None = None
    category: str | None = None
    status: Status | None = None
    resolution: Resolution | None = None

    @field_validator("category")
    @classmethod
    def supported_category(cls, value: str | None) -> str | None:
        return None if value is None else validate_category(value)

    @field_validator("bbox")
    @classmethod
    def valid_bbox(cls, value: str | None) -> str | None:
        if value is not None:
            parse_bbox(value)
        return value


class ReportFilters(ReadFilters):
    limit: Annotated[int, Field(ge=1, le=500)] = 100
    offset: Annotated[int, Field(ge=0)] = 0

    @field_validator("limit", "offset", mode="before")
    @classmethod
    def query_integer(cls, value: object) -> object:
        # Query parameters arrive as text, even with a strict model.
        return int(value) if isinstance(value, str) else value


class StatsOut(StrictModel):
    total: int
    by_category: dict[str, int]
    by_status: dict[Status, int]
    by_resolution: dict[Resolution, int]


class Open311Filters(StrictModel):
    start_date: AwareDatetime | None = None
    end_date: AwareDatetime | None = None
    service_code: str | None = None
    status: Literal["open", "closed"] | None = None

    @field_validator("service_code")
    @classmethod
    def supported_service(cls, value: str | None) -> str | None:
        return None if value is None else validate_category(value)

    @field_validator("start_date", "end_date", mode="before")
    @classmethod
    def query_datetime(cls, value: object) -> object:
        return datetime.fromisoformat(value) if isinstance(value, str) else value

    @model_validator(mode="after")
    def date_range(self) -> Self:
        if (
            self.start_date is not None
            and self.end_date is not None
            and self.start_date > self.end_date
        ):
            raise ValueError("Invalid date range")
        return self


class Open311Request(StrictModel):
    service_request_id: str
    status: Literal["open", "closed"]
    service_code: str
    service_name: str
    description: str
    lat: float
    long: float
    requested_datetime: AwareDatetime
    updated_datetime: AwareDatetime
    media_url: str


def parse_bbox(value: str) -> tuple[float, float, float, float]:
    parts = [float(part) for part in value.split(",")]
    if len(parts) != 4 or not all(math.isfinite(part) for part in parts):
        raise ValueError("Invalid bounding box")
    west, south, east, north = parts
    if not (-180 <= west <= east <= 180 and -90 <= south <= north <= 90):
        raise ValueError("Invalid bounding box bounds")
    return west, south, east, north
