import logging

import httpx
from pydantic import ValidationError

from app.schemas import ReportCreate, VerifierResult

logger = logging.getLogger(__name__)


class VerifierClient:
    def __init__(
        self,
        url: str,
        transport: httpx.BaseTransport | None = None,
        timeout: float = 10.0,
    ) -> None:
        self.url = f"{url}/verify"
        self.health_url = f"{url}/health"
        self.client = httpx.Client(
            timeout=httpx.Timeout(timeout, connect=min(3.0, timeout)),
            transport=transport,
            follow_redirects=False,
            trust_env=False,
        )

    def healthy(self) -> bool:
        try:
            response = self.client.get(self.health_url, timeout=1.0)
            response.raise_for_status()
            body = response.json()
            return isinstance(body, dict) and body.get("status") == "ok"
        except (httpx.HTTPError, ValueError):
            return False

    def verify(self, photo: bytes, report: ReportCreate) -> VerifierResult | None:
        fields = {
            "category": report.category,
            "latitude": str(report.latitude),
            "longitude": str(report.longitude),
            "captured_at": report.captured_at.isoformat(),
        }
        try:
            response = self.client.post(
                self.url,
                data=fields,
                files={"photo": ("photo.jpg", photo, "image/jpeg")},
            )
            response.raise_for_status()
            return VerifierResult.model_validate_json(response.content)
        except (httpx.HTTPError, ValidationError, ValueError):
            # Never include request bodies, coordinates, URLs, or exception strings.
            logger.warning(
                "Verifier unavailable or returned an invalid response; report pending"
            )
            return None

    def close(self) -> None:
        self.client.close()
