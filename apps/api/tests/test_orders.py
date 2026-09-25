from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app


class _FakeRepository:
    def __init__(self) -> None:
        self.captured_params: dict[str, str] = {}
        self.captured_rpc: tuple[str, dict] | None = None
        self.orders: list[dict] = []

    async def get_json(self, resource: str, params: dict[str, str]) -> list[dict]:
        self.captured_params = params
        if resource == "orders":
            return self.orders
        if resource == "order_receivables":
            return self.orders
        if resource == "order_payments":
            return []
        return []

    async def rpc(self, function: str, payload: dict):
        self.captured_rpc = (function, payload)
        if function == "cresko_create_order":
            return {
                "id": "order-1",
                "org_id": payload["p_org_id"],
                "number": "PED-00000001",
                "party_id": payload["p_party_id"],
                "variant_id": payload["p_variant_id"],
                "qty": payload["p_qty"],
                "unit_cost": payload["p_unit_cost"],
                "unit_price": payload["p_unit_price"],
                "subtotal": "10.00",
                "tax": "1.60",
                "total": "11.60",
                "currency": payload["p_currency"],
                "exchange_rate": payload["p_exchange_rate"],
                "tax_rate": payload["p_tax_rate"],
                "status": "paid",
                "paid_amount": payload["p_paid_amount"],
                "payment_method": payload["p_payment_method"],
                "expected_at": payload.get("p_expected_at"),
                "notes": payload.get("p_notes"),
                "created_by": "user-a",
                "created_at": "2026-09-24T15:00:00Z",
            }
        if function in ("cresko_pay_order", "cresko_cancel_order"):
            return {
                "id": "order-1",
                "org_id": "org-a",
                "number": "PED-00000001",
                "party_id": "p1",
                "variant_id": "v1",
                "qty": "2",
                "unit_cost": "8",
                "unit_price": "10",
                "subtotal": "20.00",
                "tax": "3.20",
                "total": "23.20",
                "currency": "USD",
                "exchange_rate": "1.000000",
                "tax_rate": "16.00",
                "status": "paid" if function == "cresko_pay_order" else "cancelled",
                "paid_amount": "20.00",
                "payment_method": "cash",
                "expected_at": None,
                "notes": None,
                "created_by": "user-a",
                "created_at": "2026-09-24T15:00:00Z",
            }
        return {"id": "order-1", "number": "PED-00000001", "status": "cancelled"}

    async def post_json(self, resource: str, payload: dict, prefer: str | None = None) -> list[dict]:
        return []


def _override(permissions: list[str]) -> _FakeRepository:
    app.dependency_overrides[get_current_membership] = lambda: context(permissions)
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    return fake


def test_list_orders_scoped_to_org() -> None:
    fake = _override([])
    client = TestClient(app)

    response = client.get("/v1/orders")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"

    app.dependency_overrides.clear()


def test_create_order_requires_permission() -> None:
    _override([])
    client = TestClient(app)

    response = client.post(
        "/v1/orders",
        json={
            "party_id": "p1",
            "variant_id": "v1",
            "qty": 2,
            "unit_price": 10,
            "paid_amount": 20,
        },
    )

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_create_order_calls_rpc_with_org() -> None:
    fake = _override(["sales.checkout"])
    client = TestClient(app)

    response = client.post(
        "/v1/orders",
        json={
            "party_id": "p1",
            "variant_id": "v1",
            "qty": 2,
            "unit_cost": 8,
            "unit_price": 10,
            "currency": "USD",
            "paid_amount": 20,
            "payment_method": "cash",
            "notes": "Bajo pedido",
        },
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_create_order"
    assert payload["p_org_id"] == "org-a"
    assert payload["p_party_id"] == "p1"
    assert payload["p_qty"] == "2"
    assert payload["p_paid_amount"] == "20"
    assert response.json()["number"] == "PED-00000001"

    app.dependency_overrides.clear()


def test_pay_order_requires_finance_receive() -> None:
    _override([])
    client = TestClient(app)

    response = client.post("/v1/orders/order-1/pay", json={"amount": 5, "method": "cash"})

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_pay_order_calls_rpc() -> None:
    fake = _override(["finance.receive"])
    client = TestClient(app)

    response = client.post("/v1/orders/order-1/pay", json={"amount": 5, "method": "transfer"})

    assert response.status_code == 200
    function, payload = fake.captured_rpc
    assert function == "cresko_pay_order"
    assert payload["p_org_id"] == "org-a"
    assert payload["p_order_id"] == "order-1"
    assert payload["p_amount"] == "5"

    app.dependency_overrides.clear()


def test_cancel_order_calls_rpc() -> None:
    fake = _override(["sales.checkout"])
    client = TestClient(app)

    response = client.post("/v1/orders/order-1/cancel")

    assert response.status_code == 200
    function, payload = fake.captured_rpc
    assert function == "cresko_cancel_order"
    assert payload == {"p_org_id": "org-a", "p_order_id": "order-1"}

    app.dependency_overrides.clear()


def test_order_receivables_scoped_to_org() -> None:
    fake = _override([])
    client = TestClient(app)

    response = client.get("/v1/orders/receivables")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"

    app.dependency_overrides.clear()