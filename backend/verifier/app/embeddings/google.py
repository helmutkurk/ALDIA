"""Google Gemini Embedding 2 through the Gemini API (`embedContent`, API key).

Gemini Embedding 2 places text and images in one space. The Gemini API is the
only documented path with a plain API key (`x-goog-api-key`); Vertex AI needs
OAuth tokens. `task_type` is not supported by this model, so texts are sent
without a task prefix (the docs advise none for cross-modal comparisons).
"""

import base64

import httpx
from pydantic import SecretStr

from app.embeddings.base import EmbeddingUnavailable, Vector, float_vector, normalized

DEFAULT_MODEL = "gemini-embedding-2"
BASE_URL = "https://generativelanguage.googleapis.com/v1beta"


def _values(body: object) -> object:
    # The REST shape is not shown in the docs; accept both documented SDK shapes.
    if isinstance(body, dict):
        if isinstance(body.get("embedding"), dict):
            return body["embedding"].get("values")
        embeddings = body.get("embeddings")
        if (
            isinstance(embeddings, list)
            and embeddings
            and isinstance(embeddings[0], dict)
        ):
            return embeddings[0].get("values")
    return None


class GoogleGeminiEmbedder:
    name = "google"

    def __init__(
        self,
        api_key: SecretStr,
        *,
        model: str = DEFAULT_MODEL,
        dimension: int = 1024,
        timeout: float = 10.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        if not 128 <= dimension <= 3072:
            raise ValueError("Gemini Embedding 2 supports 128 to 3072 dimensions")
        self._dimension = dimension
        self._url = f"{BASE_URL}/models/{model}:embedContent"
        self._client = httpx.Client(
            timeout=timeout,
            transport=transport,
            headers={
                "x-goog-api-key": api_key.get_secret_value(),
                "Content-Type": "application/json",
            },
        )

    def _embed(self, part: dict[str, object]) -> Vector:
        body = {
            "content": {"parts": [part]},
            "output_dimensionality": self._dimension,
        }
        try:
            response = self._client.post(self._url, json=body)
            response.raise_for_status()
            return normalized(float_vector(_values(response.json())))
        except (httpx.HTTPError, ValueError) as exc:
            raise EmbeddingUnavailable("Google embedding request failed") from exc

    def embed_image(self, jpeg: bytes) -> Vector:
        return self._embed(
            {
                "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": base64.b64encode(jpeg).decode("ascii"),
                }
            }
        )

    def embed_text(self, text: str) -> Vector:
        return self._embed({"text": text})

    def close(self) -> None:
        self._client.close()
