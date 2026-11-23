"""Amazon Nova Multimodal Embeddings on Amazon Bedrock (InvokeModel, API key).

Request schema `nova-multimodal-embed-v1`, task `SINGLE_EMBEDDING`. Images are
indexed with `GENERIC_INDEX`; the category texts act as queries against images
(`IMAGE_RETRIEVAL`), as the Nova user guide recommends for text-to-image search.
Authentication: a Bedrock API key as `Authorization: Bearer`.
"""

import base64
from urllib.parse import quote

import httpx
from pydantic import SecretStr

from app.embeddings.base import EmbeddingUnavailable, Vector, float_vector, normalized

DEFAULT_MODEL = "amazon.nova-2-multimodal-embeddings-v1:0"
DIMENSIONS = (256, 384, 1024, 3072)


class AmazonNovaEmbedder:
    name = "amazon"

    def __init__(
        self,
        api_key: SecretStr,
        *,
        region: str,
        model: str = DEFAULT_MODEL,
        dimension: int = 1024,
        timeout: float = 6.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        if dimension not in DIMENSIONS:
            raise ValueError(f"Amazon Nova embeddings support {DIMENSIONS}")
        self._dimension = dimension
        self._url = (
            f"https://bedrock-runtime.{region}.amazonaws.com"
            f"/model/{quote(model, safe='')}/invoke"
        )
        self._client = httpx.Client(
            timeout=timeout,
            transport=transport,
            headers={
                "Authorization": f"Bearer {api_key.get_secret_value()}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )

    def _embed(self, purpose: str, content: dict[str, object]) -> Vector:
        body = {
            "schemaVersion": "nova-multimodal-embed-v1",
            "taskType": "SINGLE_EMBEDDING",
            "singleEmbeddingParams": {
                "embeddingPurpose": purpose,
                "embeddingDimension": self._dimension,
                **content,
            },
        }
        try:
            response = self._client.post(self._url, json=body)
            response.raise_for_status()
            embeddings = response.json()["embeddings"]
            return normalized(float_vector(embeddings[0]["embedding"]))
        except (httpx.HTTPError, ValueError, KeyError, IndexError, TypeError) as exc:
            raise EmbeddingUnavailable("Amazon embedding request failed") from exc

    def embed_image(self, jpeg: bytes) -> Vector:
        return self._embed(
            "GENERIC_INDEX",
            {
                "image": {
                    "format": "jpeg",
                    "detailLevel": "STANDARD_IMAGE",
                    "source": {"bytes": base64.b64encode(jpeg).decode("ascii")},
                }
            },
        )

    def embed_text(self, text: str) -> Vector:
        return self._embed(
            "IMAGE_RETRIEVAL", {"text": {"truncationMode": "END", "value": text}}
        )

    def close(self) -> None:
        self._client.close()
