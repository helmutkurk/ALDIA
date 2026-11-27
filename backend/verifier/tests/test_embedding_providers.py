"""Vector helpers, provider response parsing and model mode through the app.

All provider traffic goes to httpx.MockTransport; nothing leaves the machine.
"""

import base64
import json
import logging
import math
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO

import httpx
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from pydantic import SecretStr
from test_embeddings import (
    KEY,
    PROVIDERS,
    Seen,
    Transport,
    amazon_transport,
    axis,
    category_check,
    model_client,
    text_vector,
)
from test_verifier import fields, photo

from app.checks.category_prompts import PROMPTS
from app.config import Settings
from app.embeddings.amazon import AmazonNovaEmbedder
from app.embeddings.base import EmbeddingUnavailable, cosine, float_vector, normalized
from app.embeddings.google import GoogleGeminiEmbedder
from app.main import create_app

PROMPT_COUNT = sum(len(texts) for texts in PROMPTS.values())
Handler = Callable[[httpx.Request], httpx.Response]


def google(handler: Handler, **options: object) -> GoogleGeminiEmbedder:
    return GoogleGeminiEmbedder(
        SecretStr(KEY),
        transport=httpx.MockTransport(handler),
        **options,  # type: ignore[arg-type]
    )


def amazon(handler: Handler, **options: object) -> AmazonNovaEmbedder:
    return AmazonNovaEmbedder(
        SecretStr(KEY),
        region="us-east-1",
        transport=httpx.MockTransport(handler),
        **options,  # type: ignore[arg-type]
    )


def answer(response: httpx.Response) -> Handler:
    return lambda _request: response


# --- normalized / cosine / float_vector -------------------------------------


def test_normalized_scales_to_unit_length() -> None:
    assert normalized([3, -4]) == pytest.approx([0.6, -0.8])
    assert sum(v * v for v in normalized([1e-150, 2e-150])) == pytest.approx(1.0)


@pytest.mark.parametrize(
    "vector",
    [
        [],
        [0.0, 0.0],
        [math.nan, 1.0],
        [math.inf, 1.0],
        [-math.inf],
        [1e200, 1e200],  # finite items whose squared sum overflows
    ],
)
def test_normalized_rejects_unusable_vectors(vector: list[float]) -> None:
    with pytest.raises(EmbeddingUnavailable):
        normalized(vector)


def test_cosine_of_unit_vectors() -> None:
    assert cosine([1.0, 0.0], [1.0, 0.0]) == pytest.approx(1.0)
    assert cosine([1.0, 0.0], [0.0, 1.0]) == pytest.approx(0.0)
    assert cosine([1.0, 0.0], [-1.0, 0.0]) == pytest.approx(-1.0)


@pytest.mark.parametrize(("left", "right"), [([1.0], [1.0, 0.0]), ([1.0, 0.0], [])])
def test_cosine_rejects_dimension_mismatch(
    left: list[float], right: list[float]
) -> None:
    with pytest.raises(EmbeddingUnavailable, match="dimensions"):
        cosine(left, right)


def test_float_vector_converts_ints_to_floats() -> None:
    vector = float_vector([1, 2.5, -3])
    assert vector == [1.0, 2.5, -3.0]
    assert all(type(item) is float for item in vector)


@pytest.mark.parametrize(
    "value",
    [
        None,
        [],
        (1.0, 2.0),
        "1,2",
        {"values": [1.0]},
        [True, 1.0],
        [False],
        [1.0, None],
        [1.0, "2"],
        [[1.0, 2.0]],
    ],
)
def test_float_vector_rejects_non_numeric_lists(value: object) -> None:
    with pytest.raises(EmbeddingUnavailable):
        float_vector(value)


# --- Google response shapes --------------------------------------------------


def test_google_prefers_the_single_embedding_shape() -> None:
    body = {"embedding": {"values": [1.0, 0.0]}, "embeddings": [{"values": [0.0, 1.0]}]}
    embedder = google(answer(httpx.Response(200, json=body)))
    assert embedder.embed_text("x") == pytest.approx([1.0, 0.0])


@pytest.mark.parametrize(
    "content",
    [
        b"{}",
        b"[]",
        b"null",
        b'"values"',
        b'{"embedding": [1.0, 2.0]}',
        b'{"embedding": {}}',
        b'{"embedding": {"values": []}}',
        b'{"embedding": {"values": null}}',
        b'{"embedding": {"values": "1,2"}}',
        b'{"embedding": {"values": [true, 1.0]}}',
        b'{"embedding": {"values": [NaN, 1.0]}}',
        b'{"embedding": {"values": [Infinity, 1.0]}}',
        b'{"embedding": {"values": [0, 0]}}',
        b'{"embeddings": []}',
        b'{"embeddings": [[1.0, 2.0]]}',
        b'{"embeddings": [{"vals": [1.0]}]}',
        b'{"embeddings": {"values": [1.0]}}',
        b"<html>quota</html>",
        b"",
    ],
)
def test_google_rejects_unusable_response_bodies(content: bytes) -> None:
    embedder = google(answer(httpx.Response(200, content=content)))
    with pytest.raises(EmbeddingUnavailable) as caught:
        embedder.embed_text("x")
    assert KEY not in str(caught.value)
    assert "googleapis" not in str(caught.value)


@pytest.mark.parametrize("status", [400, 401, 403, 429, 500, 503])
def test_google_http_errors_are_generic(status: int) -> None:
    body = {"error": {"message": f"API key {KEY} not valid"}}
    embedder = google(answer(httpx.Response(status, json=body)))
    with pytest.raises(EmbeddingUnavailable, match="^Google embedding request failed$"):
        embedder.embed_image(b"jpeg")


def test_google_timeouts_are_generic() -> None:
    def slow(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("timed out", request=request)

    with pytest.raises(EmbeddingUnavailable):
        google(slow).embed_text("x")


def test_google_custom_model_and_dimension() -> None:
    seen: Seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"embedding": {"values": [1.0]}})

    google(handler, model="gemini-embedding-2-preview", dimension=128).embed_text("x")
    assert seen[0].url.path == "/v1beta/models/gemini-embedding-2-preview:embedContent"
    assert json.loads(seen[0].content)["output_dimensionality"] == 128


@pytest.mark.parametrize("dimension", [127, 3073])
def test_google_rejects_dimensions_outside_its_range(dimension: int) -> None:
    with pytest.raises(ValueError, match="128 to 3072"):
        GoogleGeminiEmbedder(SecretStr(KEY), dimension=dimension)


# --- Amazon request and response edge cases ----------------------------------


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"embeddings": {"0": {"embedding": [1.0]}}},
        {"embeddings": "abc"},
        {"embeddings": [None]},
        {"embeddings": [{"embedding": None}]},
        {"embeddings": [{"embedding": [True]}]},
        {"embeddings": [{"vector": [1.0]}]},
        [{"embedding": [1.0]}],
    ],
)
def test_amazon_rejects_unusable_response_bodies(body: object) -> None:
    with pytest.raises(EmbeddingUnavailable) as caught:
        amazon(answer(httpx.Response(200, json=body))).embed_text("x")
    assert KEY not in str(caught.value)


def test_amazon_encodes_a_custom_model_id_into_one_path_segment() -> None:
    seen: Seen = []
    with model_client(
        "amazon",
        amazon_transport,
        PROVIDERS[0][2],
        {"pothole": 1.0},
        seen,
        embedding_model="acme.custom-embed_v2:1",
        embedding_region="eu-central-1",
        embedding_dimension=256,
    ) as client:
        category_check(client, "pothole")
    assert {str(request.url) for request in seen} == {
        "https://bedrock-runtime.eu-central-1.amazonaws.com/model/"
        "acme.custom-embed_v2%3A1/invoke"
    }
    assert (
        json.loads(seen[0].content)["singleEmbeddingParams"]["embeddingDimension"]
        == 256
    )


@pytest.mark.parametrize("model", [".", ".."])
def test_dot_segment_model_ids_cannot_change_the_amazon_path(model: str) -> None:
    seen: Seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"embeddings": [{"embedding": [1.0]}]})

    try:
        config = Settings.model_validate(
            {
                "verifier_mode": "model",
                "embedding_provider": "amazon",
                "aws_bearer_token_bedrock": KEY,
                "embedding_model": model,
            }
        )
    except ValueError:
        return  # Rejecting the id is an acceptable fix.
    amazon(handler, model=config.embedding_model).embed_text("x")
    segments = seen[0].url.path.split("/")
    assert segments[:2] == ["", "model"] and segments[-1] == "invoke"
    assert len(segments) == 4


@pytest.mark.parametrize(
    ("make", "content"),
    [
        (amazon, b'{"embeddings": [{"embedding": [1' + b"0" * 400 + b"]}]}"),
        (google, b'{"embedding": {"values": [1' + b"0" * 400 + b"]}}"),
    ],
)
def test_huge_integers_in_a_vector_are_unavailable_not_internal_errors(
    make: Callable[[Handler], AmazonNovaEmbedder | GoogleGeminiEmbedder],
    content: bytes,
) -> None:
    with pytest.raises(EmbeddingUnavailable):
        make(answer(httpx.Response(200, content=content))).embed_text("x")


# --- model mode through the app ----------------------------------------------


@pytest.mark.parametrize(("provider", "transport", "keys"), PROVIDERS)
def test_prompts_are_embedded_once_across_many_requests(
    provider: str, transport: Transport, keys: dict[str, object]
) -> None:
    seen: Seen = []
    with model_client(provider, transport, keys, {"pothole": 1.0}, seen) as client:
        assert len(seen) == PROMPT_COUNT  # warmed up during startup
        for _ in range(10):
            assert category_check(client, "pothole")["code"] == "category_match"
    assert len(seen) == PROMPT_COUNT + 10


@pytest.mark.parametrize(("provider", "transport", "keys"), PROVIDERS)
def test_concurrent_requests_reuse_the_warmed_prompts(
    provider: str, transport: Transport, keys: dict[str, object]
) -> None:
    seen: Seen = []
    with model_client(provider, transport, keys, {"graffiti": 1.0}, seen) as client:

        def run(_index: int) -> object:
            return category_check(client, "graffiti")["code"]

        with ThreadPoolExecutor(max_workers=8) as pool:
            codes = list(pool.map(run, range(24)))
    assert codes == ["category_match"] * 24
    assert len(seen) == PROMPT_COUNT + 24


def test_image_and_text_dimension_mismatch_answers_503() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        params = json.loads(request.content)["singleEmbeddingParams"]
        vector = (
            [1.0, 0.0] if "image" in params else text_vector(params["text"]["value"])
        )
        return httpx.Response(200, json={"embeddings": [{"embedding": vector}]})

    config = Settings.model_validate(
        {
            "verifier_mode": "model",
            "embedding_provider": "amazon",
            "aws_bearer_token_bedrock": KEY,
        }
    )
    app = create_app(config, embedding_transport=httpx.MockTransport(handler))
    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.post(
            "/verify", data=fields(), files={"photo": ("p.jpg", photo(), "image/jpeg")}
        )
    assert response.status_code == 503
    assert response.json() == {
        "error": {
            "code": "classifier_unavailable",
            "message": "Verificación no disponible.",
        }
    }


def sent_image(seen: Seen) -> Image.Image:
    params = json.loads(seen[-1].content)["singleEmbeddingParams"]
    sent = Image.open(BytesIO(base64.b64decode(params["image"]["source"]["bytes"])))
    sent.load()
    return sent


def upload(client: TestClient, data: bytes, name: str, mime: str) -> None:
    response = client.post(
        "/verify", data=fields(), files={"photo": (name, data, mime)}
    )
    assert response.status_code == 200, response.text
    assert response.json()["mode"] == "model"


def encoded(image: Image.Image, fmt: str, **options: object) -> bytes:
    buffer = BytesIO()
    image.save(buffer, format=fmt, **options)
    return buffer.getvalue()


def amazon_client(seen: Seen) -> TestClient:
    return model_client(
        "amazon", amazon_transport, PROVIDERS[0][2], {"pothole": 1.0}, seen
    )


@pytest.mark.parametrize("mode", ["RGBA", "LA", "P", "L"])
def test_png_uploads_reach_the_provider_as_rgb_jpeg(mode: str) -> None:
    source = Image.open(BytesIO(photo((1024, 768)))).convert(mode)
    seen: Seen = []
    with amazon_client(seen) as client:
        upload(client, encoded(source, "PNG"), "photo.png", "image/png")
    sent = sent_image(seen)
    assert (sent.format, sent.mode, sent.size) == ("JPEG", "RGB", (512, 384))


def test_grayscale_jpeg_reaches_the_provider_as_rgb_jpeg() -> None:
    source = Image.open(BytesIO(photo())).convert("L")
    seen: Seen = []
    with amazon_client(seen) as client:
        upload(client, encoded(source, "JPEG"), "photo.jpg", "image/jpeg")
    sent = sent_image(seen)
    assert (sent.format, sent.mode, sent.size) == ("JPEG", "RGB", (512, 384))


@pytest.mark.parametrize(("orientation", "size"), [(1, (512, 384)), (6, (384, 512))])
def test_exif_rotation_is_applied_before_the_provider_sees_the_photo(
    orientation: int, size: tuple[int, int]
) -> None:
    exif = Image.Exif()
    exif[0x0112] = orientation
    exif[0x010F] = "SecretCam"
    source = Image.open(BytesIO(photo()))
    seen: Seen = []
    with amazon_client(seen) as client:
        upload(client, encoded(source, "JPEG", exif=exif), "photo.jpg", "image/jpeg")
    sent = sent_image(seen)
    assert sent.size == size
    assert not sent.getexif()
    assert b"SecretCam" not in base64.b64decode(
        json.loads(seen[-1].content)["singleEmbeddingParams"]["image"]["source"][
            "bytes"
        ]
    )


def key_leaking_transport(fail_images: bool) -> httpx.MockTransport:
    """A provider that echoes the key in its error bodies."""

    def handler(request: httpx.Request) -> httpx.Response:
        params = json.loads(request.content)["singleEmbeddingParams"]
        if fail_images and "image" in params:
            return httpx.Response(401, json={"message": f"bad key {KEY}"})
        if "image" in params:
            return httpx.Response(
                200, json={"embeddings": [{"embedding": axis({"pothole": 1.0})}]}
            )
        vector = text_vector(params["text"]["value"])
        return httpx.Response(200, json={"embeddings": [{"embedding": vector}]})

    return httpx.MockTransport(handler)


def assert_no_key_logged(caplog: pytest.LogCaptureFixture) -> None:
    assert KEY not in caplog.text
    for record in caplog.records:
        assert KEY not in record.getMessage()
        assert KEY not in repr(record.args)
        assert record.exc_info is None or KEY not in repr(record.exc_info[1])


def model_settings() -> Settings:
    return Settings.model_validate(
        {
            "verifier_mode": "model",
            "embedding_provider": "amazon",
            "aws_bearer_token_bedrock": KEY,
        }
    )


@pytest.mark.parametrize("fail_images", [False, True])
def test_keys_never_appear_in_logs_or_responses(
    caplog: pytest.LogCaptureFixture, fail_images: bool
) -> None:
    caplog.set_level(logging.DEBUG)
    app = create_app(
        model_settings(), embedding_transport=key_leaking_transport(fail_images)
    )
    with TestClient(app, raise_server_exceptions=False) as client:
        health = client.get("/health")
        response = client.post(
            "/verify", data=fields(), files={"photo": ("p.jpg", photo(), "image/jpeg")}
        )
    assert response.status_code == (503 if fail_images else 200)
    assert KEY not in health.text and KEY not in response.text
    assert KEY not in "".join(f"{k}{v}" for k, v in response.headers.items())
    assert caplog.records  # the request was actually logged
    assert_no_key_logged(caplog)


def test_keys_never_appear_when_startup_fails(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.DEBUG)
    transport = httpx.MockTransport(
        answer(httpx.Response(403, json={"message": f"bad key {KEY}"}))
    )
    app = create_app(model_settings(), embedding_transport=transport)
    with pytest.raises(EmbeddingUnavailable) as caught, TestClient(app):
        pass
    assert KEY not in str(caught.value)
    assert KEY not in repr(caught.value.__cause__)
    assert_no_key_logged(caplog)
