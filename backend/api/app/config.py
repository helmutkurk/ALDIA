from pathlib import Path
from urllib.parse import urlsplit

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
    max_request_bytes: int = Field(default=65536, gt=0)
    public_post_rate_limit: int = Field(default=60, gt=0)
    public_post_window_seconds: int = Field(default=60, gt=0)
    verifier_timeout_seconds: float = Field(default=10.0, gt=0, le=60)
    cors_origins: str = "http://localhost:5173"
    env: str = "production"
    auth_dev_tokens: bool = False

    staff_token: str | None = Field(default=None, repr=False, exclude=True)
    supervisor_token: str | None = Field(default=None, repr=False, exclude=True)

    @field_validator("cors_origins")
    @classmethod
    def explicit_origins(cls, value: str) -> str:
        for origin in (part.strip() for part in value.split(",") if part.strip()):
            parsed = urlsplit(origin)
            if (
                parsed.scheme not in {"http", "https"}
                or not parsed.hostname
                or parsed.username is not None
                or parsed.password is not None
                or parsed.path
                or parsed.query
                or parsed.fragment
                or "*" in origin
            ):
                raise ValueError("CORS_ORIGINS must contain explicit HTTP(S) origins")
            try:
                _ = parsed.port
            except ValueError as exc:
                raise ValueError("Invalid origin port") from exc
        return value

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
