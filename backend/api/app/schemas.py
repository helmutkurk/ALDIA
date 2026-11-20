import math
from datetime import UTC, date, datetime, timedelta
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
from app.state_machine import State, StateGroup

Status = Literal["pending", "verified", "rejected"]
Resolution = Literal["open", "acknowledged", "fixed", "closed"]


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
    code: str | None = None


class Verification(StrictModel):
    passed: bool
    mode: Literal["stub", "heuristic", "model"]
    checks: list[Check]


class VerifierResult(Verification):
    phash: Annotated[str, Field(pattern=r"^[0-9a-f]{16}$")]

    @model_validator(mode="after")
    def consistent_checks(self) -> Self:
        names = [check.name for check in self.checks]
        required = {"image", "place", "freshness", "category"}
        if not required <= set(names) or len(names) != len(set(names)):
            raise ValueError("Verifier returned incomplete checks")
        if self.passed != all(check.passed for check in self.checks):
            raise ValueError("Verifier returned inconsistent checks")
        return self


class EventOut(StrictModel):
    at: AwareDatetime
    actor: str
    actor_role: Literal["system", "operator", "supervisor", "admin"]
    from_state: State | None
    to_state: State
    public_note: str | None
    internal_note: str | None = None


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
    state: State
    state_group: StateGroup
    state_changed_at: AwareDatetime
    verified_at: AwareDatetime | None
    resolved_at: AwareDatetime | None
    closed_at: AwareDatetime | None
    assignee: str | None
    assigned_at: AwareDatetime | None
    duplicate_of: UUID | None
    public_note: str | None
    events: list[EventOut] = Field(default_factory=list)


class ReportList(StrictModel):
    items: list[ReportOut]
    total: int
    limit: int
    offset: int


class ReadFilters(StrictModel):
    bbox: str | None = None
    category: str | None = None
    status: Status | None = None
    resolution: Resolution | None = None
    state: State | None = None
    state_group: StateGroup | None = None
    assignee: str | None = None
    created_from: date | None = None
    created_to: date | None = None
    include_old: bool = False
    sort: Literal["newest", "oldest", "updated", "age_in_state"] = "newest"

    @field_validator("created_from", "created_to", mode="before")
    @classmethod
    def query_date(cls, value: object) -> object:
        return date.fromisoformat(value) if isinstance(value, str) else value

    @field_validator("include_old", mode="before")
    @classmethod
    def query_boolean(cls, value: object) -> object:
        if isinstance(value, str):
            if value.lower() in {"true", "1"}:
                return True
            if value.lower() in {"false", "0"}:
                return False
        return value

    @model_validator(mode="after")
    def date_range(self) -> Self:
        if (
            self.created_from
            and self.created_to
            and self.created_from > self.created_to
        ):
            raise ValueError("Invalid date range")
        return self

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
    limit: Annotated[int, Field(ge=1, le=100)] = 100
    offset: Annotated[int, Field(ge=0)] = 0

    @field_validator("limit", "offset", mode="before")
    @classmethod
    def query_integer(cls, value: object) -> object:
        # Query parameters arrive as text, even with a strict model.
        return int(value) if isinstance(value, str) else value


class DurationStats(StrictModel):
    median: float | None
    p90: float | None
    n: int


class ResolutionStats(DurationStats):
    mean: float | None


class WeeklyStats(StrictModel):
    week: str
    recibidos: int
    resueltos: int


class CategoryStats(StrictModel):
    category: str
    total: int
    resueltos: int
    abiertos: int
    cerrados: int
    mediana_reparacion_horas: float | None
    p90_reparacion_horas: float | None
    n_resueltos: int


class StatsOut(StrictModel):
    total: int
    by_category: dict[str, int]
    by_status: dict[Status, int]
    by_resolution: dict[Resolution, int]
    recibidos: int
    rechazados_verificador: int
    abiertos: int
    resueltos: int
    cerrados_sin_solucion: int
    tasa_resolucion: float | None
    tasa_resolucion_n: int
    resolucion_horas: ResolutionStats
    primera_respuesta_horas: DurationStats
    antiguedad_abiertos: dict[str, int]
    sla_cumplido: float | None
    vencidos: int
    by_state: dict[str, int]
    by_state_group: dict[str, int]
    weekly: list[WeeklyStats]
    por_categoria: list[CategoryStats]
    top_categorias: list[CategoryStats]


class TransitionIn(StrictModel):
    to: State
    public_note: Annotated[str | None, Field(max_length=280)] = None
    internal_note: Annotated[str | None, Field(max_length=500)] = None
    duplicate_of: UUID | None = None

    @field_validator("duplicate_of", mode="before")
    @classmethod
    def parse_uuid(cls, value: object) -> object:
        return UUID(value) if isinstance(value, str) else value


class AssignmentIn(StrictModel):
    assignee: Annotated[str | None, Field(max_length=60)]


class ExportFilters(ReadFilters):
    delimiter: Literal["comma", "semicolon"] = "comma"


class ClusterFilters(ReadFilters):
    bbox: str
    zoom: Annotated[int, Field(ge=0, le=20)]

    @field_validator("zoom", mode="before")
    @classmethod
    def query_zoom(cls, value: object) -> object:
        return int(value) if isinstance(value, str) else value


class Cluster(StrictModel):
    lat: float
    lon: float
    count: int
    ids: list[UUID]


class ClustersOut(StrictModel):
    clusters: list[Cluster]
    total: int


class NearbyFilters(StrictModel):
    lat: Annotated[float, Field(ge=-90, le=90)]
    lon: Annotated[float, Field(ge=-180, le=180)]
    category: str
    radius_m: Annotated[float, Field(ge=20, le=500)] = 150.0

    _category = field_validator("category")(validate_category)

    @field_validator("lat", "lon", "radius_m", mode="before")
    @classmethod
    def query_float(cls, value: object) -> object:
        return float(value) if isinstance(value, str) else value


class NearbyItem(ReportOut):
    thumbnail_url: str
    distance_m: float


class NearbyOut(StrictModel):
    items: list[NearbyItem]


class QueueFilters(ReportFilters):
    tab: Literal["review", "rejected"] = "review"


class QueueItem(ReportOut):
    age_hours: float | None


class QueueOut(StrictModel):
    items: list[QueueItem]
    total: int
    limit: int
    offset: int


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
