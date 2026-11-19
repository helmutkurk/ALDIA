from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra="forbid")

    database_url: str = "postgresql+psycopg://aldia:aldia@db:5432/aldia"
    photo_dir: Path = Path("/data/photos")
    verifier_url: str = "http://verifier:8001"
    max_upload_bytes: int = Field(default=8388608, gt=0)
    cors_origins: str = "http://localhost:5173"

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
