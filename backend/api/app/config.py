from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=None, extra="forbid", hide_input_in_errors=True
    )

    database_url: str = "postgresql+psycopg://aldia:aldia@db:5432/aldia"
    photo_dir: Path = Path("/data/photos")
    verifier_url: str = "http://verifier:8001"
    max_upload_bytes: int = Field(default=8388608, gt=0)
    cors_origins: str = "http://localhost:5173"
    env: str = "production"
    auth_dev_tokens: bool = False

    staff_token: str | None = Field(default=None, repr=False, exclude=True)
    supervisor_token: str | None = Field(default=None, repr=False, exclude=True)

    @property
    def dev_tokens_enabled(self) -> bool:
        return self.env == "dev" and self.auth_dev_tokens

    @field_validator("staff_token", "supervisor_token")
    @classmethod
    def valid_token(cls, value: str | None) -> str | None:
        if not value:
            return None
        if len(value) < 32:
            raise ValueError(
                "Staff authentication tokens must be at least 32 characters"
            )
        return value

    @field_validator("verifier_url")
    @classmethod
    def http_url(cls, value: str) -> str:
        if not value.startswith(("http://", "https://")):
            raise ValueError("VERIFIER_URL must use HTTP or HTTPS")
        return value.rstrip("/")

    @property
    def allowed_origins(self) -> list[str]:
        return [
            origin.strip() for origin in self.cors_origins.split(",") if origin.strip()
        ]
