"""Settings validation for model mode and the modes that must never call a provider."""

import math

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from test_embeddings import KEY
from test_verifier import fields, photo

from app.config import Settings
from app.main import create_app

AMAZON = {
    "verifier_mode": "model",
    "embedding_provider": "amazon",
    "aws_bearer_token_bedrock": KEY,
}
GOOGLE = {
    "verifier_mode": "model",
    "embedding_provider": "google",
    "gemini_api_key": KEY,
}


def amazon_settings(**overrides: object) -> Settings:
    return Settings.model_validate({**AMAZON, **overrides})


@pytest.mark.parametrize("dimension", [128, 256, 1024, 3072])
def test_dimension_inside_range_is_accepted(dimension: int) -> None:
    assert amazon_settings(embedding_dimension=dimension).embedding_dimension == (
        dimension
    )


@pytest.mark.parametrize("dimension", [0, 127, 3073, -1024])
def test_dimension_outside_range_is_rejected(dimension: int) -> None:
    with pytest.raises(ValidationError, match="embedding_dimension"):
        amazon_settings(embedding_dimension=dimension)


@pytest.mark.parametrize("top_k", [1, 4, 7])
def test_top_k_inside_range_is_accepted(top_k: int) -> None:
    assert amazon_settings(embedding_top_k=top_k).embedding_top_k == top_k


@pytest.mark.parametrize("top_k", [0, -1, 8])
def test_top_k_outside_range_is_rejected(top_k: int) -> None:
    with pytest.raises(ValidationError, match="embedding_top_k"):
        amazon_settings(embedding_top_k=top_k)


@pytest.mark.parametrize("value", [-1.0, 0.0, 0.25, 1.0])
def test_min_similarity_inside_range_is_accepted(value: float) -> None:
    assert amazon_settings(embedding_min_similarity=value).embedding_min_similarity == (
        value
    )


@pytest.mark.parametrize("value", [-1.01, 1.01, math.nan, math.inf, -math.inf])
def test_min_similarity_outside_range_is_rejected(value: float) -> None:
    with pytest.raises(ValidationError, match="embedding_min_similarity"):
        amazon_settings(embedding_min_similarity=value)


@pytest.mark.parametrize("seconds", [0.001, 10, 60])
def test_timeout_inside_range_is_accepted(seconds: float) -> None:
    config = amazon_settings(embedding_timeout_seconds=seconds)
    assert config.embedding_timeout_seconds == seconds


@pytest.mark.parametrize("seconds", [0, -1, 60.5, math.inf, math.nan])
def test_timeout_outside_range_is_rejected(seconds: float) -> None:
    with pytest.raises(ValidationError, match="embedding_timeout_seconds"):
        amazon_settings(embedding_timeout_seconds=seconds)


@pytest.mark.parametrize("region", ["us-east-1", "eu-central-1", "ap-southeast-2"])
def test_plain_regions_are_accepted(region: str) -> None:
    assert amazon_settings(embedding_region=region).embedding_region == region


@pytest.mark.parametrize(
    "region",
    [
        "us-east-1.evil.com/x",
        "us-east-1/x",
        "evil.com",
        "us-east-1@evil.com",
        "us-east-1#",
        "us-east-1?x=1",
        "US-EAST-1",
        "us east 1",
        "us-east-1\n",
        "",
    ],
)
def test_regions_that_could_change_the_host_are_rejected(region: str) -> None:
    with pytest.raises(ValidationError, match="embedding_region"):
        amazon_settings(embedding_region=region)


@pytest.mark.parametrize(
    "model",
    ["amazon.nova-2-multimodal-embeddings-v1:0", "gemini-embedding-2", "my_model-1"],
)
def test_plain_model_ids_are_accepted(model: str) -> None:
    assert amazon_settings(embedding_model=model).embedding_model == model


@pytest.mark.parametrize(
    "model",
    [
        "a/b",
        "../invoke",
        "x?y=1",
        "x#y",
        "x y",
        "x%2Fy",
        "https://evil.com",
        "model\n",
        "",
    ],
)
def test_model_ids_with_url_syntax_are_rejected(model: str) -> None:
    with pytest.raises(ValidationError, match="embedding_model"):
        amazon_settings(embedding_model=model)


@pytest.mark.parametrize(
    ("settings", "variable"),
    [
        ({**AMAZON, "aws_bearer_token_bedrock": ""}, "AWS_BEARER_TOKEN_BEDROCK"),
        ({**GOOGLE, "gemini_api_key": ""}, "GEMINI_API_KEY"),
        (
            {"verifier_mode": "model", "embedding_provider": "amazon"},
            "AWS_BEARER_TOKEN_BEDROCK",
        ),
        (
            {"verifier_mode": "model", "embedding_provider": "google"},
            "GEMINI_API_KEY",
        ),
    ],
)
def test_model_mode_rejects_missing_or_empty_keys(
    settings: dict[str, object], variable: str
) -> None:
    with pytest.raises(ValidationError, match=variable):
        Settings.model_validate(settings)


def test_model_mode_rejects_the_other_providers_key() -> None:
    with pytest.raises(ValidationError, match="AWS_BEARER_TOKEN_BEDROCK"):
        Settings.model_validate(
            {
                "verifier_mode": "model",
                "embedding_provider": "amazon",
                "gemini_api_key": "x",
            }
        )


def test_model_mode_requires_a_provider() -> None:
    with pytest.raises(ValidationError, match="EMBEDDING_PROVIDER"):
        Settings.model_validate({"verifier_mode": "model", "gemini_api_key": KEY})


@pytest.mark.parametrize("provider", ["openai", "Amazon", ""])
def test_unknown_providers_are_rejected(provider: str) -> None:
    with pytest.raises(ValidationError, match="embedding_provider"):
        amazon_settings(embedding_provider=provider)


def test_unknown_settings_are_rejected() -> None:
    with pytest.raises(ValidationError, match="embedding_api_url"):
        amazon_settings(embedding_api_url="https://evil.com")


def test_settings_are_read_from_the_usual_environment_names(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("VERIFIER_MODE", "model")
    monkeypatch.setenv("EMBEDDING_PROVIDER", "google")
    monkeypatch.setenv("GEMINI_API_KEY", KEY)
    monkeypatch.setenv("EMBEDDING_TOP_K", "3")
    config = Settings()
    assert config.embedding_provider == "google"
    assert config.embedding_top_k == 3
    assert config.gemini_api_key is not None
    assert config.gemini_api_key.get_secret_value() == KEY


@pytest.mark.xfail(
    strict=True,
    reason=(
        "Bug: model-level validators report the whole input dict as input_value, "
        "so a ValidationError (startup log) prints the raw provider key; "
        "Settings needs hide_input_in_errors=True."
    ),
)
@pytest.mark.parametrize(
    "settings",
    [
        # Wrong provider key: the key that was given is echoed back.
        {
            "verifier_mode": "model",
            "embedding_provider": "amazon",
            "gemini_api_key": KEY,
        },
        # Unrelated mistake in an otherwise valid model-mode configuration.
        {"exposure_min_mean": 200, "exposure_max_mean": 100, **AMAZON},
    ],
)
def test_validation_errors_never_contain_keys(settings: dict[str, object]) -> None:
    with pytest.raises(ValidationError) as caught:
        Settings.model_validate(settings)
    assert KEY not in str(caught.value)


def test_amazon_dimension_outside_its_supported_set_fails_at_startup() -> None:
    # 128 is valid for Settings (Google range) but Nova only supports four sizes.
    with pytest.raises(ValueError, match="support"):
        create_app(amazon_settings(embedding_dimension=128))


def refusing_transport(seen: list[httpx.Request]) -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        raise AssertionError("heuristic mode must not call an embedding provider")

    return httpx.MockTransport(handler)


@pytest.mark.parametrize(
    "settings",
    [
        {},
        {"verifier_mode": "stub"},
        # Model fields present but mode not "model": all of them are ignored.
        {
            "verifier_mode": "stub",
            "embedding_provider": "amazon",
            "embedding_top_k": 7,
            "embedding_min_similarity": 0.9,
        },
        {
            "verifier_mode": "heuristic",
            **{k: v for k, v in GOOGLE.items() if k != "verifier_mode"},
        },
        {"verifier_mode": "stub", "embedding_provider": "google", "gemini_api_key": ""},
    ],
)
def test_heuristic_and_stub_modes_never_call_a_provider(
    settings: dict[str, object],
) -> None:
    seen: list[httpx.Request] = []
    app = create_app(
        Settings.model_validate(settings), embedding_transport=refusing_transport(seen)
    )
    with TestClient(app) as client:
        assert client.get("/health").json() == {"status": "ok", "mode": "heuristic"}
        for _ in range(3):
            response = client.post(
                "/verify",
                data=fields(),
                files={"photo": ("photo.jpg", photo(), "image/jpeg")},
            )
            assert response.status_code == 200
            body = response.json()
            assert body["mode"] == "heuristic"
            assert body["checks"][-1]["code"] == "category_stub"
    assert seen == []
