"""Presentation module separation must retain schema isolation and caching."""

from pathlib import Path

from app.config import Settings
from app.main import create_app


def test_openapi_instances_have_independent_examples_and_upload_limits(
    tmp_path: Path,
) -> None:
    first = create_app(
        Settings(
            database_url="sqlite://", photo_dir=tmp_path / "a", max_upload_bytes=1234
        )
    )
    second = create_app(
        Settings(
            database_url="sqlite://", photo_dir=tmp_path / "b", max_upload_bytes=5678
        )
    )
    try:
        schema = first.openapi()
        other = second.openapi()
        assert first.openapi() is schema
        assert second.openapi() is other
        upload = schema["paths"]["/api/reports"]["post"]
        other_upload = other["paths"]["/api/reports"]["post"]
        description = upload["requestBody"]["content"]["multipart/form-data"]["schema"][
            "properties"
        ]["photo"]["description"]
        assert "1234 bytes" in description
        other_description = other_upload["requestBody"]["content"][
            "multipart/form-data"
        ]["schema"]["properties"]["photo"]["description"]
        assert "5678 bytes" in other_description
        example = upload["responses"]["201"]["content"]["application/json"]["example"]
        other_example = other_upload["responses"]["201"]["content"]["application/json"][
            "example"
        ]
        assert example == other_example
        assert example["events"][0]["to_state"] == "nuevo"
        example["verification"]["checks"][0]["detail"] = "changed by a consumer"
        assert other_example["verification"]["checks"][0]["detail"] == "800x600 jpeg"
        assert (
            upload["responses"]["200"]["content"]["application/json"]["example"]
            == other_example
        )
    finally:
        for app in (first, second):
            app.state.services.verifier.close()
            app.state.services.database.engine.dispose()
