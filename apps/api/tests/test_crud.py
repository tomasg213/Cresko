from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app


class _FakeRepository:
    def __init__(self) -> None:
        self.captured_rpc: tuple[str, dict] | None = None
        self.captured_params: dict[str, str] = {}
        self.captured_patch: tuple[str, dict, dict] | None = None
        self.captured_delete: tuple[str, dict] | None = None
        self.configs: list[dict] = []
        self.payments: list[dict] = []

    async def get_json(self, resource: str, params: dict[str, str]) -> list[dict]:
        self.captured_params = params
        if resource == "replenishment_config":
            return self.configs
        if resource == "payments":
            return self.payments
        return []

    async def post_json(self, resource: str, payload: dict, prefer: str | None = None) -> list[dict]:
        return []

    async def patch_json(
        self, resource: str, payload: dict, params: dict[str, str], prefer: str | None = None
    ) -> list[dict]:
        self.captured_patch = (resource, payload, params)
        if resource == "replenishment_config":
            return self.configs
        if resource == "parties":
            return [{"id": "party-1", "org_id": "org-a", "name": "Actualizado", "is_customer": True, "is_supplier": False, "document_type": "rif", "document_id": None, "phone": None, "email": None, "is_active": True}]
        return []

    async def delete_json(self, resource: str, params: dict[str, str]) -> None:
        self.captured_delete = (resource, params)

    async def rpc(self, function: str, payload: dict):
        self.captured_rpc = (function, payload)
        if function in ("cresko_update_purchase_order", "cresko_create_purchase_order"):
            return {
                "id": "po-1",
                "org_id": "org-a",
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
        return {"id": "x"}


def _override(repository: _FakeRepository, permissions: list[str]):
    app.dependency_overrides[get_current_membership] = lambda: context(permissions)
    app.dependency_overrides[get_supabase_repository] = lambda: repository


def test_update_purchase_order_calls_rpc_with_org() -> None:
    fake = _FakeRepository()
    _override(fake, ["purchasing.write"])
    client = TestClient(app)

    response = client.patch(
        "/v1/purchasing/orders/po-1",
        json={"supplier_id": "s1", "warehouse_id": "w1", "currency": "VES", "lines": [{"variant_id": "v1", "qty": 3, "unit_cost": 9}]},
    )

    assert response.status_code == 200
    assert fake.captured_rpc[0] == "cresko_update_purchase_order"
    assert fake.captured_rpc[1]["p_org_id"] == "org-a"
    assert fake.captured_rpc[1]["p_po_id"] == "po-1"
    app.dependency_overrides.clear()


def test_delete_purchase_order_calls_rpc_with_org() -> None:
    fake = _FakeRepository()
    _override(fake, ["purchasing.write"])
    client = TestClient(app)

    response = client.delete("/v1/purchasing/orders/po-1")

    assert response.status_code == 204
    assert fake.captured_rpc == ("cresko_delete_purchase_order", {"p_org_id": "org-a", "p_po_id": "po-1"})
    app.dependency_overrides.clear()


def test_delete_purchase_order_requires_permission() -> None:
    fake = _FakeRepository()
    _override(fake, [])
    client = TestClient(app)

    response = client.delete("/v1/purchasing/orders/po-1")

    assert response.status_code == 403
    app.dependency_overrides.clear()


def test_update_party_patches_scoped_to_org() -> None:
    fake = _FakeRepository()
    _override(fake, ["catalog.write"])
    client = TestClient(app)

    response = client.patch("/v1/parties/party-1", json={"name": "Actualizado"})

    assert response.status_code == 200
    assert fake.captured_patch[0] == "parties"
    assert fake.captured_patch[1] == {"name": "Actualizado"}
    assert fake.captured_patch[2] == {"org_id": "eq.org-a", "id": "eq.party-1"}
    app.dependency_overrides.clear()


def test_delete_party_calls_rpc() -> None:
    fake = _FakeRepository()
    _override(fake, ["catalog.write"])
    client = TestClient(app)

    response = client.delete("/v1/parties/party-1")

    assert response.status_code == 204
    assert fake.captured_rpc == ("cresko_delete_party", {"p_org_id": "org-a", "p_party_id": "party-1"})
    app.dependency_overrides.clear()


def test_list_replenishment_configs_scoped_to_org() -> None:
    fake = _FakeRepository()
    fake.configs = [
        {
            "id": "c1",
            "variant_id": "v1",
            "warehouse_id": "w1",
            "min_qty": "5",
            "max_qty": "20",
            "pack_multiple": "3",
            "preferred_supplier_id": None,
            "lead_time_days": 0,
            "is_active": True,
            "variant": {"id": "v1", "name": "Camisa", "sku": "CM-1"},
            "warehouse": {"id": "w1", "name": "Principal", "code": "ALM01"},
        }
    ]
    _override(fake, [])
    client = TestClient(app)

    response = client.get("/v1/replenishment/configs")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"
    assert response.json()[0]["variant"]["name"] == "Camisa"
    app.dependency_overrides.clear()


def test_update_replenishment_config_patches_scoped() -> None:
    fake = _FakeRepository()
    fake.configs = [
        {
            "id": "c1",
            "variant_id": "v1",
            "warehouse_id": "w1",
            "min_qty": "5",
            "max_qty": "20",
            "pack_multiple": "3",
            "preferred_supplier_id": None,
            "lead_time_days": 0,
            "is_active": True,
        }
    ]
    _override(fake, ["replenishment.write"])
    client = TestClient(app)

    response = client.patch("/v1/replenishment/config/c1", json={"min_qty": 7, "preferred_supplier_id": None})

    assert response.status_code == 200
    assert fake.captured_patch[0] == "replenishment_config"
    assert fake.captured_patch[1] == {"min_qty": "7", "preferred_supplier_id": None}
    assert fake.captured_patch[2] == {"org_id": "eq.org-a", "id": "eq.c1"}
    app.dependency_overrides.clear()


def test_delete_replenishment_config_scoped() -> None:
    fake = _FakeRepository()
    _override(fake, ["replenishment.write"])
    client = TestClient(app)

    response = client.delete("/v1/replenishment/config/c1")

    assert response.status_code == 204
    assert fake.captured_delete == ("replenishment_config", {"org_id": "eq.org-a", "id": "eq.c1"})
    app.dependency_overrides.clear()


def test_ar_payments_list_and_void() -> None:
    fake = _FakeRepository()
    fake.payments = [
        {
            "id": "p1",
            "invoice_id": "inv-1",
            "amount": "100",
            "currency": "USD",
            "method": "cash",
            "status": "posted",
            "created_at": "2026-09-18T15:00:00Z",
            "invoice": {"number": "FAC-1", "party": {"name": "Maria"}},
        }
    ]
    _override(fake, [])
    client = TestClient(app)

    response = client.get("/v1/ar/payments")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"
    assert response.json()[0]["invoice_number"] == "FAC-1"
    assert response.json()[0]["party_name"] == "Maria"

    fake2 = _FakeRepository()
    _override(fake2, ["finance.receive"])
    response = client.post("/v1/ar/payments/p1/void")
    assert response.status_code == 204
    assert fake2.captured_rpc == ("cresko_void_payment", {"p_org_id": "org-a", "p_payment_id": "p1"})
    app.dependency_overrides.clear()


def test_ap_payments_list_and_void() -> None:
    fake = _FakeRepository()
    _override(fake, [])
    client = TestClient(app)

    response = client.get("/v1/ap/payments")

    assert response.status_code == 200
    assert fake.captured_params["entry_type"] == "eq.payment"
    assert fake.captured_params["org_id"] == "eq.org-a"

    fake2 = _FakeRepository()
    _override(fake2, ["finance.pay"])
    response = client.post("/v1/ap/payments/led-1/void")
    assert response.status_code == 204
    assert fake2.captured_rpc == ("cresko_void_ap_payment", {"p_org_id": "org-a", "p_ledger_id": "led-1"})
    app.dependency_overrides.clear()