from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app
from cresko_api.schemas import OrganizationContext


class _FakeRepository:
    def __init__(self) -> None:
        self.captured_params: dict[str, str] = {}
        self.captured_rpc: tuple[str, dict] | None = None
        self.balances: list[dict] = []

    async def get_json(self, resource: str, params: dict[str, str]) -> list[dict]:
        self.captured_params = params
        if resource in ("ar_balances", "ap_balances", "ar_receivables", "ap_receivables"):
            return self.balances
        return []

    async def post_json(self, resource: str, payload: dict, prefer: str | None = None) -> list[dict]:
        return [{"id": "party-1"}]

    async def rpc(self, function: str, payload: dict):
        self.captured_rpc = (function, payload)
        if function == "cresko_replenishment_needed":
            return [
                {
                    "variant_id": "v1",
                    "variant_name": "Camisa",
                    "variant_sku": "CM-AZ-M",
                    "warehouse_id": "w1",
                    "warehouse_name": "Principal",
                    "on_hand": "2",
                    "on_order": "0",
                    "min_qty": "5",
                    "max_qty": "20",
                    "pack_multiple": "3",
                    "suggested_qty": "18",
                    "preferred_supplier_id": None,
                }
            ]
        if function in ("cresko_apply_ar_payment", "cresko_apply_ap_payment"):
            return [{"invoice_id": "inv-1", "amount": payload["p_amount"]}]
        if function == "cresko_receive_goods":
            return {
                "id": "gr-1",
                "org_id": payload["p_org_id"],
                "po_id": payload["p_po_id"],
                "number": "ENT-00000001",
                "received_at": payload.get("p_received_at") or "2026-09-18",
                "notes": payload.get("p_notes"),
                "created_by": "user-a",
                "created_at": "2026-09-18T15:00:00Z",
            }
        return {
            "id": "doc-1",
            "org_id": payload["p_org_id"],
            "supplier_id": payload["p_supplier_id"],
            "warehouse_id": payload["p_warehouse_id"],
            "number": "POC-00000001",
            "status": "ordered",
            "currency": payload["p_currency"],
            "exchange_rate": payload["p_exchange_rate"],
            "tax_rate": payload["p_tax_rate"],
            "expected_at": payload.get("p_expected_at"),
            "notes": payload.get("p_notes"),
            "created_by": "user-a",
            "created_at": "2026-09-18T15:00:00Z",
            "po_lines": [],
        }


def _context(permissions: list[str]) -> OrganizationContext:
    return context(permissions)


def test_create_po_requires_purchasing_role() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post(
        "/v1/purchasing/orders",
        json={
            "supplier_id": "s1",
            "warehouse_id": "w1",
            "currency": "VES",
            "lines": [{"variant_id": "v1", "qty": 5, "unit_cost": 10}],
        },
    )

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_create_po_calls_rpc_with_org() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["purchasing.write"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/purchasing/orders",
        json={
            "supplier_id": "s1",
            "warehouse_id": "w1",
            "currency": "VES",
            "lines": [{"variant_id": "v1", "qty": 5, "unit_cost": 10}],
        },
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_create_purchase_order"
    assert payload["p_org_id"] == "org-a"
    assert payload["p_lines"] == [{"variant_id": "v1", "qty": "5", "unit_cost": "10"}]

    app.dependency_overrides.clear()


def test_receive_goods_allows_warehouse() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["purchasing.receive"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/purchasing/orders/po-1/receive",
        json={"lines": [{"po_line_id": "pl1", "qty": 5}]},
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_receive_goods"
    assert payload["p_po_id"] == "po-1"

    app.dependency_overrides.clear()


def test_po_list_is_scoped_to_org() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["purchasing.write"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/purchasing/orders")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"

    app.dependency_overrides.clear()


def test_ar_balances_scoped_to_org() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/ar/balances")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"

    app.dependency_overrides.clear()


def test_ar_receivables_returns_invoice_number() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    fake = _FakeRepository()
    fake.balances = [
        {
            "invoice_id": "inv-1",
            "invoice_number": "FAC-00000001",
            "party_id": "p1",
            "party_name": "Maria",
            "currency": "VES",
            "balance": "5905.91",
        }
    ]
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/ar/receivables")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"
    assert response.json()[0]["invoice_number"] == "FAC-00000001"

    app.dependency_overrides.clear()


def test_ap_receivables_scoped_to_org() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/ap/receivables")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"

    app.dependency_overrides.clear()


def test_ap_receivables_returns_invoice_number() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    fake = _FakeRepository()
    fake.balances = [
        {
            "supplier_invoice_id": "si-1",
            "invoice_number": "CMP-00000001",
            "party_id": "p1",
            "party_name": "Proveedor SA",
            "currency": "USD",
            "balance": "120.00",
        }
    ]
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/ap/receivables")

    assert response.status_code == 200
    assert response.json()[0]["supplier_invoice_id"] == "si-1"
    assert response.json()[0]["invoice_number"] == "CMP-00000001"

    app.dependency_overrides.clear()


def test_general_ar_payment_requires_permission() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post(
        "/v1/ar/payments/general",
        json={"party_id": "p1", "amount": 50, "currency": "USD", "method": "cash"},
    )

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_general_ar_payment_calls_rpc() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["finance.receive"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/ar/payments/general",
        json={"party_id": "p1", "amount": 50, "currency": "USD", "method": "transfer"},
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_apply_ar_payment"
    assert payload["p_org_id"] == "org-a"
    assert payload["p_party_id"] == "p1"
    assert payload["p_amount"] == "50"

    app.dependency_overrides.clear()


def test_general_ap_payment_requires_permission() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post(
        "/v1/ap/payments/general",
        json={"party_id": "p1", "amount": 80, "currency": "USD", "method": "cash"},
    )

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_general_ap_payment_calls_rpc() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["finance.pay"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/ap/payments/general",
        json={"party_id": "p1", "amount": 80, "currency": "USD", "method": "cash"},
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_apply_ap_payment"
    assert payload["p_org_id"] == "org-a"
    assert payload["p_party_id"] == "p1"
    assert payload["p_amount"] == "80"

    app.dependency_overrides.clear()


def test_replenishment_needed_calls_rpc() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["inventory.write"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/replenishment/needed")

    assert response.status_code == 200
    assert fake.captured_rpc == ("cresko_replenishment_needed", {"p_org_id": "org-a"})

    app.dependency_overrides.clear()


def test_po_requires_at_least_one_line() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["purchasing.write"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post(
        "/v1/purchasing/orders",
        json={"supplier_id": "s1", "warehouse_id": "w1", "currency": "VES", "lines": []},
    )

    assert response.status_code == 422

    app.dependency_overrides.clear()
