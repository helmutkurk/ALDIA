from typing import Literal, Self

from pydantic import Field, SecretStr, model_validator
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

    # Model mode: zero-shot category check with an external embedding provider.
    embedding_provider: Literal["amazon", "google"] | None = None
    embedding_model: str | None = Field(default=None, pattern=r"^[A-Za-z0-9.:_-]+$")
    embedding_region: str = Field(default="us-east-1", pattern=r"^[a-z0-9-]+$")
    embedding_dimension: int = Field(default=1024, ge=128, le=3072)
    embedding_top_k: int = Field(default=1, ge=1, le=7)
    embedding_min_similarity: float = Field(default=0.0, ge=-1, le=1)
    # Below the API's 10 s verifier timeout, so an outage still answers 503 in time.
    embedding_timeout_seconds: float = Field(default=6.0, gt=0, le=60)
    # Provider keys under their usual names; never logged or returned.
    aws_bearer_token_bedrock: SecretStr | None = None
    gemini_api_key: SecretStr | None = None

    @model_validator(mode="after")
    def ordered_exposure(self) -> Self:
        if self.exposure_min_mean > self.exposure_max_mean:
            raise ValueError("EXPOSURE_MIN_MEAN must not exceed EXPOSURE_MAX_MEAN")
        return self

    @model_validator(mode="after")
    def model_mode_is_configured(self) -> Self:
        if self.verifier_mode != "model":
            return self
        if self.embedding_provider is None:
            raise ValueError("VERIFIER_MODE=model requires EMBEDDING_PROVIDER")
        key = (
            self.aws_bearer_token_bedrock
            if self.embedding_provider == "amazon"
            else self.gemini_api_key
        )
        if key is None or not key.get_secret_value():
            name = (
                "AWS_BEARER_TOKEN_BEDROCK"
                if self.embedding_provider == "amazon"
                else "GEMINI_API_KEY"
            )
            raise ValueError(
                f"EMBEDDING_PROVIDER={self.embedding_provider} needs {name}"
            )
        return self
