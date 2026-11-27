"""The API with a verifier in model mode (embedding category check)."""

import httpx
import pytest
from fastapi.testclient import TestClient
from test_reports import fake_verifier, submit


def use_verifier(client: TestClient, reply: httpx.Response) -> None:
    services = client.app.state.services
    services.verifier.client.close()
    services.verifier.client = httpx.Client(
        transport=httpx.MockTransport(lambda _request: reply)
    )


def model_reply(passed: bool, code: str, detail: str) -> httpx.Response:
    body = fake_verifier(
        httpx.Request("POST", "http://verifier/verify", content=b'name="photo"')
    ).json()
    body["mode"] = "model"
    body["passed"] = passed
    body["checks"][-1] = {
        "name": "category",
        "passed": passed,
        "detail": detail,
        "code": code,
    }
    return httpx.Response(200, json=body)


def test_model_category_match_verifies_and_keeps_the_mode(client: TestClient) -> None:
    use_verifier(
        client,
        model_reply(
            True, "category_match", "coincide con la categoría (similitud 0.47)"
        ),
    )
    report = submit(client).json()
    assert report["status"] == "verified" and report["state"] == "nuevo"
    assert report["verification"]["mode"] == "model"
    category = next(
        c for c in report["verification"]["checks"] if c["name"] == "category"
    )
    assert category["passed"] is True


@pytest.mark.parametrize(
    ("code", "detail"),
    [
        ("category_mismatch", "la foto parece mostrar: Bache"),
        ("category_no_problem", "la foto no parece mostrar un problema urbano"),
        ("category_low_similarity", "similitud insuficiente con la categoría (0.12)"),
    ],
)
def test_model_category_rejection_rejects_with_its_explanation(
    client: TestClient, code: str, detail: str
) -> None:
    use_verifier(client, model_reply(False, code, detail))
    report = submit(client).json()
    assert report["status"] == "rejected"
    assert report["state"] == "rechazado_verificador"
    category = next(
        c for c in report["verification"]["checks"] if c["name"] == "category"
    )
    assert category["passed"] is False and category["detail"] == detail


def test_classifier_outage_keeps_the_report_pending(client: TestClient) -> None:
    use_verifier(
        client,
        httpx.Response(
            503,
            json={
                "error": {
                    "code": "classifier_unavailable",
                    "message": "Verificación no disponible.",
                }
            },
        ),
    )
    report = submit(client).json()
    assert report["status"] == "pending"
    assert report["state"] == "pendiente_verificacion"
    assert report["verification"] is None
