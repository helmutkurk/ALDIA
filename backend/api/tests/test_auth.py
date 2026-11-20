"""Staff v0.4 integration guarantees; all credentials here are synthetic."""

from fastapi.testclient import TestClient


def test_auth_config_is_secure_by_default(client: TestClient) -> None:
    assert client.get("/api/auth/config").json() == {
        "enabled": True,
        "dev_tokens": False,
    }
    client.app.state.services.settings.staff_token = "o" * 32
    assert (
        client.get("/api/queue", headers={"X-Staff-Token": "o" * 32}).status_code == 401
    )


def test_unknown_login_is_generic_and_origin_is_checked(client: TestClient) -> None:
    data = {"username": "unknown", "password": "synthetic-password"}
    reply = client.post("/api/auth/login", json=data)
    assert reply.status_code == 401
    assert reply.json()["error"]["code"] == "unauthorized"
    assert (
        client.post(
            "/api/auth/login", json=data, headers={"Origin": "https://evil.invalid"}
        ).status_code
        == 403
    )
