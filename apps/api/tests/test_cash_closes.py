from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app


class _FakeRepository:
    def __init__(self) -> None:
        self.captured_params: dict[str, str] = {}
        self.captured_rpc: tuple[str, dict] | None = None
        self.rows: list[dict] = []

    async def get_json(self, resource: str, params: dict[str, str]) -> list[dict]:
        self.captured_params = params
        if resource == "cash_closes":
            return self.rows
        if resource == "cash_close_transactions":
            return self.rows
        return []

    async def rpc(self, function: str, payload: dict):
        self.captured_rpc = (function, payload)
        if function == "cresko_ensure_open_close":
            return {
                "id": "cc-1",
                "org_id": payload["p_org_id"],
                "number": "CC-00000001",
                "opened_at": "2026-09-25T14:00:00Z",
                "closed_at": None,
                "status": "open",
                "opened_by": "user-a",
                "closed_by": None,
            }
        if function == "cresko_close_cash_register":
            return {
                "cash_close_id": "cc-1",
                "number": "CC-00000001",
                "opened_at": "2026-09-25T14:00:00Z",
                "closed_at": "2026-09-25T18:00:00Z",
                "transactions": 3,
                "total_usd": "100.00",
                "paid_usd": "90.00",
                "balance_usd": "10.00",
                "cash_usd": "40.00",
                "card_usd": "30.00",
                "biopago_usd": "20.00",
                "credit_usd": "10.00",
            }
        return {}


def _override(permissions: list[str]) -> _FakeRepository:
    app.dependency_overrides[get_current_membership] = lambda: context(permissions)
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    return fake


def test_ensure_open_close_calls_rpc() -> None:
    fake = _override([])
    client = TestClient(app)

    response = client.post("/v1/cash-closes/ensure")

    assert response.status_code == 200
    function, payload = fake.captured_rpc
    assert function == "cresko_ensure_open_close"
    assert payload == {"p_org_id": "org-a"}
    assert response.json()["number"] == "CC-00000001"

    app.dependency_overrides.clear()


def test_list_cash_closes_scoped_to_org() -> None:
    fake = _override([])
    client = TestClient(app)

    response = client.get("/v1/cash-closes")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"

    app.dependency_overrides.clear()


def test_current_cash_close_returns_null_when_empty() -> None:
    fake = _override([])
    fake.rows = []
    client = TestClient(app)

    response = client.get("/v1/cash-closes/current")

    assert response.status_code == 200
    assert response.json() is None

    app.dependency_overrides.clear()


def test_close_requires_finance_receive() -> None:
    _override([])
    client = TestClient(app)

    response = client.post("/v1/cash-closes/cc-1/close")

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_close_calls_rpc() -> None:
    fake = _override(["finance.receive"])
    client = TestClient(app)

    response = client.post("/v1/cash-closes/cc-1/close")

    assert response.status_code == 200
    function, payload = fake.captured_rpc
    assert function == "cresko_close_cash_register"
    assert payload == {"p_org_id": "org-a", "p_cash_close_id": "cc-1"}
    assert response.json()["cash_usd"] == "40.00"
    assert response.json()["credit_usd"] == "10.00"

    app.dependency_overrides.clear()