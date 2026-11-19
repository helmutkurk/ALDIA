from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra="forbid")

    verifier_mode: Literal["stub", "model"] = "stub"
    max_age_seconds: int = Field(default=600, ge=0)
