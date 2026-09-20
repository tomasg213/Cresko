from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app


class _FakeRepository:
    def __init__(self) -> None:
        self.captured_rpc: tuple[str, dict] | None = None

    async def get_json(self, resource: str, params: dict[str, str]) -> list[dict]:
        return [{"rate_date": "2026-09-19", "source": "manual"}]

    async def rpc(self, function: str, payload: dict) -> dict:
        self.captured_rpc = (function, payload)
        if function == "cresko_current_exchange_rate":
            return "36.50"
        return {"rate": "36.50", "rate_date": "2026-09-19", "source": "manual"}


def test_get_rate_returns_current() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["catalog.read"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.get("/v1/fx/rate")

    assert response.status_code == 200
    assert response.json()["rate"] == "36.50"

    app.dependency_overrides.clear()


def test_set_rate_requires_org_manage() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["catalog.read"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post("/v1/fx/rate", json={"rate": 36.5})

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_set_rate_calls_upsert_with_org_and_today() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["org.manage"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post("/v1/fx/rate", json={"rate": 36.5})

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_upsert_exchange_rate"
    assert payload["p_org_id"] == "org-a"
    assert payload["p_rate"] == "36.5"
    assert payload["p_source"] == "manual"

    app.dependency_overrides.clear()


def test_fetch_rate_uses_bcv_source(monkeypatch) -> None:
    from cresko_api import fx

    async def fake_fetch() -> float:
        return 36.75

    monkeypatch.setattr(fx, "fetch_bcv_rate", fake_fetch)
    app.dependency_overrides[get_current_membership] = lambda: context(["org.manage"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post("/v1/fx/fetch")

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_upsert_exchange_rate"
    assert payload["p_rate"] == "36.75"
    assert payload["p_source"] == "bcv"

    app.dependency_overrides.clear()