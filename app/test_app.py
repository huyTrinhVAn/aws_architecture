import pytest

from app import app as flask_app


@pytest.fixture
def client():
    flask_app.config["TESTING"] = True
    with flask_app.test_client() as client:
        yield client


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.data == b"ok"


def test_create_expense_requires_amount_and_category(client):
    response = client.post("/expenses", json={"note": "missing required fields"})
    assert response.status_code == 400
    assert response.get_json() == {"error": "amount and category_id are required"}
