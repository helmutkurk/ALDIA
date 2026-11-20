from typing import Literal, Self

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=None, extra="forbid", allow_inf_nan=False
    )

    # Keep the old deployment value as an alias, never as a response mode.
    verifier_mode: Literal["heuristic", "stub", "model"] = "heuristic"
    max_age_seconds: int = Field(default=600, ge=0)
    sharpness_min: float = Field(default=80.0, ge=0)
    exposure_min_mean: float = Field(default=12.0, ge=0, le=255)
    exposure_max_mean: float = Field(default=243.0, ge=0, le=255)
    exposure_max_clipped_ratio: float = Field(default=0.95, ge=0, le=1)
    screen_min_correlation: float = Field(default=0.85, gt=0, le=1)

    @model_validator(mode="after")
    def ordered_exposure(self) -> Self:
        if self.exposure_min_mean > self.exposure_max_mean:
            raise ValueError("EXPOSURE_MIN_MEAN must not exceed EXPOSURE_MAX_MEAN")
        return self
