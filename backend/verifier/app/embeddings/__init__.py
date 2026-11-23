"""Embedding providers for the model-mode category check."""

import httpx

from app.config import Settings
from app.embeddings import amazon, google
from app.embeddings.amazon import AmazonNovaEmbedder
from app.embeddings.base import Embedder, EmbeddingUnavailable
from app.embeddings.google import GoogleGeminiEmbedder

__all__ = ["Embedder", "EmbeddingUnavailable", "build_embedder"]


def build_embedder(
    settings: Settings, transport: httpx.BaseTransport | None = None
) -> AmazonNovaEmbedder | GoogleGeminiEmbedder:
    """Create the configured provider; Settings already validated its key."""
    if settings.embedding_provider == "amazon":
        assert settings.aws_bearer_token_bedrock is not None
        return AmazonNovaEmbedder(
            settings.aws_bearer_token_bedrock,
            region=settings.embedding_region,
            model=settings.embedding_model or amazon.DEFAULT_MODEL,
            dimension=settings.embedding_dimension,
            timeout=settings.embedding_timeout_seconds,
            transport=transport,
        )
    assert settings.gemini_api_key is not None
    return GoogleGeminiEmbedder(
        settings.gemini_api_key,
        model=settings.embedding_model or google.DEFAULT_MODEL,
        dimension=settings.embedding_dimension,
        timeout=settings.embedding_timeout_seconds,
        transport=transport,
    )
