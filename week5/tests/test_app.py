import pytest

from app import app


@pytest.fixture
def client():
    # Configure Flask for testing
    app.config.update(
        TESTING=True,
        SECRET_KEY="test-secret-key"
    )

    with app.test_client() as client:
        yield client


def test_homepage(client):
    # Check that the homepage works
    response = client.get("/")

    assert response.status_code == 200
    assert b"My Linux Server - Week 5" in response.data


def test_empty_history(client):
    # A new session should have no conversation history
    response = client.get("/api/history")

    assert response.status_code == 200
    assert response.get_json() == {"messages": []}


@pytest.mark.parametrize("message", [
    "",
    "   ",
    "a" * 1001,
    123
])
def test_invalid_messages(client, message):
    # Invalid messages must be rejected
    response = client.post(
        "/api/chat",
        json={"message": message}
    )

    assert response.status_code == 400


def test_chat_with_mocked_services(client, monkeypatch):
    # Test the chat without real Ollama or MariaDB
    saved_messages = []

    monkeypatch.setattr(
        "app.get_messages",
        lambda session_id, limit=10: []
    )

    monkeypatch.setattr(
        "app.save_exchange",
        lambda *args: saved_messages.append(args)
    )

    class FakeResponse:
        def raise_for_status(self):
            pass

        def json(self):
            return {
                "message": {
                    "content": "Linux is an operating system."
                }
            }

    monkeypatch.setattr(
        "app.requests.post",
        lambda *args, **kwargs: FakeResponse()
    )

    response = client.post(
        "/api/chat",
        json={"message": "What is Linux?"}
    )

    assert response.status_code == 200
    assert response.get_json()["reply"] == (
        "Linux is an operating system."
    )

    # Verify that the conversation was saved
    assert len(saved_messages) == 1
    assert saved_messages[0][1] == "What is Linux?"
    assert saved_messages[0][2] == "Linux is an operating system."


def test_health_endpoint(client, monkeypatch):
    # Simulate a commit SHA provided by deployment
    test_sha = "a" * 40
    monkeypatch.setenv("DEPLOY_SHA", test_sha)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json() == {
        "status": "ok",
        "commit": test_sha
    }
