"""Model mode with fake Amazon and Google responses; nothing leaves the machine."""

import base64
import json
from collections.abc import Callable
from io import BytesIO

import httpx
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from pydantic import SecretStr
from test_verifier import fields, photo

from app.checks.category_prompts import NO_PROBLEM, PROMPTS
from app.checks.embedding_classifier import EmbeddingClassifier, provider_jpeg
from app.config import Settings
from app.embeddings.amazon import AmazonNovaEmbedder
from app.embeddings.base import EmbeddingUnavailable
from app.embeddings.google import GoogleGeminiEmbedder
from app.main import create_app

LABELS = list(PROMPTS)
KEY = "test-key-not-real"
Seen = list[httpx.Request]
Transport = Callable[[dict[str, float], Seen], httpx.MockTransport]


def axis(weights: dict[str, float]) -> list[float]:
    """A vector in a fake space with one axis per label."""
    return [weights.get(label, 0.0) for label in LABELS]


def text_vector(text: str) -> list[float]:
    label = next(name for name, texts in PROMPTS.items() if text in texts)
    return axis({label: 1.0})


def amazon_transport(image: dict[str, float], seen: Seen) -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        params = json.loads(request.content)["singleEmbeddingParams"]
        vector = (
            axis(image) if "image" in params else text_vector(params["text"]["value"])
        )
        return httpx.Response(
            200, json={"embeddings": [{"embeddingType": "X", "embedding": vector}]}
        )

    return httpx.MockTransport(handler)


def google_transport(image: dict[str, float], seen: Seen) -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        part = json.loads(request.content)["content"]["parts"][0]
        vector = axis(image) if "inline_data" in part else text_vector(part["text"])
        return httpx.Response(200, json={"embedding": {"values": vector}})

    return httpx.MockTransport(handler)


PROVIDERS: list[tuple[str, Transport, dict[str, object]]] = [
    ("amazon", amazon_transport, {"aws_bearer_token_bedrock": KEY}),
    ("google", google_transport, {"gemini_api_key": KEY}),
]


def model_client(
    provider: str,
    transport: Transport,
    keys: dict[str, object],
    image: dict[str, float],
    seen: Seen | None = None,
    **settings: object,
) -> TestClient:
    config = Settings.model_validate(
        {"verifier_mode": "model", "embedding_provider": provider, **keys, **settings}
    )
    app = create_app(
        config, embedding_transport=transport(image, [] if seen is None else seen)
    )
    return TestClient(app)


def category_check(client: TestClient, category: str) -> dict[str, object]:
    response = client.post(
        "/verify",
        data=fields(category=category),
        files={"photo": ("photo.jpg", photo(), "image/jpeg")},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["mode"] == "model"
    check: dict[str, object] = body["checks"][-1]
    assert check["name"] == "category"
    assert body["passed"] is check["passed"]
    return check


@pytest.mark.parametrize(("provider", "transport", "keys"), PROVIDERS)
def test_model_mode_decides_by_rank(
    provider: str, transport: Transport, keys: dict[str, object]
) -> None:
    image = {"pothole": 0.9, "sidewalk": 0.4, "graffiti": 0.1}
    with model_client(provider, transport, keys, image) as client:
        assert client.get("/health").json() == {"status": "ok", "mode": "model"}
        assert category_check(client, "pothole")["code"] == "category_match"
        # Default top_k=1: only the best category passes.
        assert category_check(client, "sidewalk")["code"] == "category_mismatch"
        mismatch = category_check(client, "graffiti")
        assert mismatch["code"] == "category_mismatch"
        assert mismatch["detail"] == "la foto parece mostrar: Bache"


@pytest.mark.parametrize(("provider", "transport", "keys"), PROVIDERS)
def test_top_k_two_also_accepts_the_runner_up(
    provider: str, transport: Transport, keys: dict[str, object]
) -> None:
    image = {"pothole": 0.9, "sidewalk": 0.4, "graffiti": 0.1}
    with model_client(provider, transport, keys, image, embedding_top_k=2) as client:
        assert category_check(client, "sidewalk")["code"] == "category_match"
        assert category_check(client, "graffiti")["code"] == "category_mismatch"


@pytest.mark.parametrize(("provider", "transport", "keys"), PROVIDERS)
def test_no_problem_photo_fails(
    provider: str, transport: Transport, keys: dict[str, object]
) -> None:
    image = {NO_PROBLEM: 0.9, "pothole": 0.2}
    with model_client(provider, transport, keys, image, embedding_top_k=1) as client:
        assert category_check(client, "pothole")["code"] == "category_no_problem"


@pytest.mark.parametrize(("provider", "transport", "keys"), PROVIDERS)
def test_min_similarity_is_enforced(
    provider: str, transport: Transport, keys: dict[str, object]
) -> None:
    image = {"pothole": 0.5, "sidewalk": 0.5}
    with model_client(
        provider, transport, keys, image, embedding_min_similarity=0.9
    ) as client:
        assert category_check(client, "pothole")["code"] == "category_low_similarity"


def test_amazon_request_shape() -> None:
    seen: Seen = []
    with model_client(
        "amazon",
        amazon_transport,
        PROVIDERS[0][2],
        {"pothole": 1.0},
        seen,
        embedding_region="us-west-2",
        embedding_dimension=384,
    ) as client:
        category_check(client, "pothole")
    assert len(seen) == sum(len(t) for t in PROMPTS.values()) + 1
    request = seen[-1]
    assert str(request.url) == (
        "https://bedrock-runtime.us-west-2.amazonaws.com/model/"
        "amazon.nova-2-multimodal-embeddings-v1%3A0/invoke"
    )
    assert request.headers["authorization"] == f"Bearer {KEY}"
    body = json.loads(request.content)
    assert body["schemaVersion"] == "nova-multimodal-embed-v1"
    assert body["taskType"] == "SINGLE_EMBEDDING"
    params = body["singleEmbeddingParams"]
    assert params["embeddingPurpose"] == "GENERIC_INDEX"
    assert params["embeddingDimension"] == 384
    assert params["image"]["format"] == "jpeg"
    sent = Image.open(BytesIO(base64.b64decode(params["image"]["source"]["bytes"])))
    assert sent.format == "JPEG" and max(sent.size) <= 512 and not sent.getexif()
    text = json.loads(seen[0].content)["singleEmbeddingParams"]
    assert text["embeddingPurpose"] == "IMAGE_RETRIEVAL"
    assert text["text"]["truncationMode"] == "END"


def test_google_request_shape() -> None:
    seen: Seen = []
    with model_client(
        "google",
        google_transport,
        PROVIDERS[1][2],
        {"pothole": 1.0},
        seen,
        embedding_dimension=768,
    ) as client:
        category_check(client, "pothole")
    request = seen[-1]
    assert str(request.url) == (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        "gemini-embedding-2:embedContent"
    )
    assert request.headers["x-goog-api-key"] == KEY
    assert "authorization" not in request.headers
    body = json.loads(request.content)
    assert body["output_dimensionality"] == 768
    inline = body["content"]["parts"][0]["inline_data"]
    assert inline["mime_type"] == "image/jpeg"
    assert Image.open(BytesIO(base64.b64decode(inline["data"]))).format == "JPEG"


def test_google_accepts_list_response_shape() -> None:
    transport = httpx.MockTransport(
        lambda _r: httpx.Response(200, json={"embeddings": [{"values": [3.0, 4.0]}]})
    )
    embedder = GoogleGeminiEmbedder(SecretStr(KEY), transport=transport)
    assert embedder.embed_text("x") == pytest.approx([0.6, 0.8])


@pytest.mark.parametrize(
    "response",
    [
        httpx.Response(500, json={"error": "boom"}),
        httpx.Response(200, json={"embeddings": []}),
        httpx.Response(200, json={"embeddings": [{"embedding": [0.0, 0.0]}]}),
        httpx.Response(200, json={"embeddings": [{"embedding": ["a"]}]}),
        httpx.Response(200, content=b"not json"),
    ],
)
def test_bad_provider_answers_raise_generic_errors(response: httpx.Response) -> None:
    embedder = AmazonNovaEmbedder(
        SecretStr(KEY),
        region="us-east-1",
        transport=httpx.MockTransport(lambda _r: response),
    )
    with pytest.raises(EmbeddingUnavailable) as caught:
        embedder.embed_text("x")
    assert KEY not in str(caught.value) and "amazonaws" not in str(caught.value)


def test_provider_outage_answers_503_so_the_api_keeps_the_report_pending() -> None:
    def flaky(request: httpx.Request) -> httpx.Response:
        params = json.loads(request.content)["singleEmbeddingParams"]
        if "image" in params:
            raise httpx.ConnectError("down", request=request)
        vector = text_vector(params["text"]["value"])
        return httpx.Response(200, json={"embeddings": [{"embedding": vector}]})

    config = Settings.model_validate(
        {
            "verifier_mode": "model",
            "embedding_provider": "amazon",
            "aws_bearer_token_bedrock": KEY,
        }
    )
    app = create_app(config, embedding_transport=httpx.MockTransport(flaky))
    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.post(
            "/verify",
            data=fields(),
            files={"photo": ("photo.jpg", photo(), "image/jpeg")},
        )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "classifier_unavailable"
    assert KEY not in response.text


def test_startup_fails_when_prompts_cannot_be_embedded() -> None:
    config = Settings.model_validate(
        {
            "verifier_mode": "model",
            "embedding_provider": "google",
            "gemini_api_key": KEY,
        }
    )
    app = create_app(
        config,
        embedding_transport=httpx.MockTransport(lambda _r: httpx.Response(403)),
    )
    with pytest.raises(EmbeddingUnavailable), TestClient(app):
        pass


def test_keys_are_hidden_in_settings_repr() -> None:
    config = Settings.model_validate(
        {
            "verifier_mode": "model",
            "embedding_provider": "amazon",
            "aws_bearer_token_bedrock": KEY,
        }
    )
    assert KEY not in repr(config) and KEY not in str(config.model_dump())


def test_amazon_rejects_unsupported_dimension() -> None:
    with pytest.raises(ValueError, match="support"):
        AmazonNovaEmbedder(SecretStr(KEY), region="us-east-1", dimension=512)


def test_provider_jpeg_is_small_and_clean() -> None:
    image = Image.open(BytesIO(photo((2000, 1500))))
    sent = Image.open(BytesIO(provider_jpeg(image)))
    assert sent.size == (512, 384) and not sent.getexif()


def test_classifier_rejects_bad_top_k() -> None:
    embedder = GoogleGeminiEmbedder(SecretStr(KEY))
    with pytest.raises(ValueError, match="top_k"):
        EmbeddingClassifier(embedder, top_k=0)
