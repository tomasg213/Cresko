from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app
from cresko_api.schemas import OrganizationContext


class _FakeRepository:
    def __init__(self) -> None:
        self.captured_params: dict[str, str] = {}
        self.captured_rpc: tuple[str, dict] | None = None
        self.rows: list[dict] = []

    async def get_json(self, resource: str, params: dict[str, str]) -> list[dict]:
        self.captured_params = params
        return self.rows

    async def rpc(self, function: str, payload: dict) -> dict:
        self.captured_rpc = (function, payload)
        return {
            "id": "mov-1",
            "variant_id": payload["p_variant_id"],
            "warehouse_id": payload["p_warehouse_id"],
            "movement_type": "adjust",
            "qty": payload["p_delta"],
            "balance_after": "10.000",
            "reason": payload.get("p_reason"),
            "created_by": "user-a",
            "created_at": "2026-09-18T12:00:00Z",
        }


def _context(permissions: list[str]) -> OrganizationContext:
    return context(permissions)


def test_adjust_stock_requires_stock_keeper_role() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post(
        "/v1/inventory/adjustments",
        json={"variant_id": "v1", "warehouse_id": "w1", "delta": 10, "reason": "entrada inicial"},
    )

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_adjust_stock_calls_rpc_with_org_and_signed_delta() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["inventory.write"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/inventory/adjustments",
        json={"variant_id": "v1", "warehouse_id": "w1", "delta": -3, "reason": "merma"},
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_adjust_stock"
    assert payload["p_org_id"] == "org-a"
    assert payload["p_delta"] == "-3"
    assert response.json()["qty"] == "-3"

    app.dependency_overrides.clear()


def test_zero_delta_is_rejected() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["inventory.write"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post(
        "/v1/inventory/adjustments",
        json={"variant_id": "v1", "warehouse_id": "w1", "delta": 0},
    )

    assert response.status_code == 422

    app.dependency_overrides.clear()


def test_stock_list_is_scoped_to_org() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/inventory/stock", params={"warehouse_id": "w1"})

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"
    assert fake.captured_params["warehouse_id"] == "eq.w1"

    app.dependency_overrides.clear()


def test_movements_list_applies_org_and_limit() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/inventory/movements", params={"limit": 20})

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"
    assert fake.captured_params["limit"] == "20"

    app.dependency_overrides.clear()


def test_warehouses_list_is_scoped_to_org() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    fake = _FakeRepository()
    fake.rows = [{"id": "w1", "name": "Almacén principal", "code": "ALM01"}]
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/inventory/warehouses")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"
    assert response.json()[0]["name"] == "Almacén principal"

    app.dependency_overrides.clear()
