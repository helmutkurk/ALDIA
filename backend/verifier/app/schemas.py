from typing import Annotated, Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator

CATEGORIES = (
    "accessibility",
    "sidewalk",
    "pothole",
    "graffiti",
    "open_drain",
    "street_light",
)


class StrictModel(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", allow_inf_nan=False)


class VerifyInput(StrictModel):
    category: str
    latitude: Annotated[float, Field(ge=-90, le=90)]
    longitude: Annotated[float, Field(ge=-180, le=180)]
    captured_at: AwareDatetime

    @field_validator("category")
    @classmethod
    def supported_category(cls, value: str) -> str:
        if value not in CATEGORIES:
            raise ValueError("Unsupported category")
        return value


class Check(StrictModel):
    name: str
    passed: bool
    detail: str
    code: str


class VerifyResult(StrictModel):
    passed: bool
    mode: Literal["heuristic", "model"]
    phash: Annotated[str, Field(pattern=r"^[0-9a-f]{16}$")]
    checks: list[Check]
