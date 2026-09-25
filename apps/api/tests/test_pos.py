from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app
from cresko_api.schemas import OrganizationContext


class _FakeRepository:
    def __init__(self) -> None:
        self.captured_params: dict[str, str] = {}
        self.captured_rpc: tuple[str, dict] | None = None
        self.invoices: list[dict] = []
        self.rate: str | None = "36.50"

    async def get_json(self, resource: str, params: dict[str, str]) -> list[dict]:
        self.captured_params = params
        if resource == "invoices":
            return self.invoices
        return []

    async def rpc(self, function: str, payload: dict) -> dict:
        self.captured_rpc = (function, payload)
        if function == "cresko_current_exchange_rate":
            return self.rate
        if function == "cresko_create_customer":
            return {
                "id": "customer-1",
                "org_id": payload["p_org_id"],
                "name": payload["p_name"],
                "document_type": "rif",
                "document_id": None,
                "phone": None,
                "email": None,
                "is_customer": True,
                "is_supplier": False,
                "is_active": True,
            }
        return {
            "id": "inv-1",
            "org_id": payload["p_org_id"],
            "number": "FAC-00000001",
            "party_id": payload.get("p_party_id"),
            "subtotal": "7300.00",
            "tax": "1168.00",
            "total": "8468.00",
            "currency": "VES",
            "exchange_rate": payload["p_exchange_rate"],
            "tax_rate": payload["p_tax_rate"],
            "status": "posted",
            "created_by": "user-a",
            "created_at": "2026-09-18T14:00:00Z",
            "invoice_lines": [],
        }


def _context(permissions: list[str]) -> OrganizationContext:
    return context(permissions)


def _valid_checkout_payload() -> dict:
    return {
        "warehouse_id": "w1",
        "price_list_code": "retail",
        "tax_rate": 16,
        "lines": [{"variant_id": "v1", "qty": 2}],
        "paid_amount": 8468,
    }


def test_checkout_requires_seller_role() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["inventory.write"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post("/v1/pos/checkout", json=_valid_checkout_payload())

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_checkout_calls_rpc_with_org_and_lines() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post("/v1/pos/checkout", json=_valid_checkout_payload())

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_checkout"
    assert payload["p_org_id"] == "org-a"
    assert payload["p_lines"] == [{"variant_id": "v1", "qty": "2"}]
    assert payload["p_exchange_rate"] == "36.50"
    assert response.json()["number"] == "FAC-00000001"

    app.dependency_overrides.clear()


def test_checkout_rejects_empty_lines() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    payload = _valid_checkout_payload()
    payload["lines"] = []
    response = client.post("/v1/pos/checkout", json=payload)

    assert response.status_code == 422

    app.dependency_overrides.clear()


def test_checkout_rejects_negative_paid_amount() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    payload = _valid_checkout_payload()
    payload["paid_amount"] = -10
    response = client.post("/v1/pos/checkout", json=payload)

    assert response.status_code == 422

    app.dependency_overrides.clear()


def test_checkout_requires_configured_rate() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    fake = _FakeRepository()
    fake.rate = None
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post("/v1/pos/checkout", json=_valid_checkout_payload())

    assert response.status_code == 400
    assert "tasa" in response.json()["detail"]

    app.dependency_overrides.clear()


def test_checkout_rejects_zero_qty() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    payload = _valid_checkout_payload()
    payload["lines"] = [{"variant_id": "v1", "qty": 0}]
    response = client.post("/v1/pos/checkout", json=payload)

    assert response.status_code == 422

    app.dependency_overrides.clear()


def test_create_customer_requires_seller_role() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post("/v1/pos/customers", json={"name": "Maria"})

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_create_customer_calls_rpc_with_org() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post("/v1/pos/customers", json={"name": "Maria", "document_type": "ci"})

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_create_customer"
    assert payload["p_org_id"] == "org-a"
    assert payload["p_name"] == "Maria"
    assert response.json()["name"] == "Maria"

    app.dependency_overrides.clear()


def test_create_customer_normalizes_ci_format() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/pos/customers",
        json={"name": "Maria", "document_type": "ci", "document_id": "20128559"},
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_create_customer"
    assert payload["p_document_id"] == "V-20.128.559"

    app.dependency_overrides.clear()


def test_create_customer_normalizes_rif_format() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/pos/customers",
        json={"name": "Comercial", "document_type": "rif", "document_id": "302345678"},
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_create_customer"
    assert payload["p_document_id"] == "J-30234567-8"

    app.dependency_overrides.clear()


def test_create_customer_normalizes_passport_format() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/pos/customers",
        json={"name": "Maria", "document_type": "passport", "document_id": "123456789"},
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_create_customer"
    assert payload["p_document_id"] == "E-123456789"

    app.dependency_overrides.clear()


def test_create_customer_normalizes_phone_with_country_code() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/pos/customers",
        json={"name": "Maria", "phone": "0412-1234567"},
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_create_customer"
    assert payload["p_phone"] == "+584121234567"

    app.dependency_overrides.clear()


def test_create_customer_keeps_existing_country_code() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context(["sales.checkout"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/pos/customers",
        json={"name": "Maria", "phone": "+584121234567"},
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_create_customer"
    assert payload["p_phone"] == "+584121234567"

    app.dependency_overrides.clear()


def test_invoice_list_is_scoped_to_org() -> None:
    app.dependency_overrides[get_current_membership] = lambda: _context([])
    fake = _FakeRepository()
    fake.invoices = [
        {
            "id": "inv-1",
            "org_id": "org-a",
            "number": "FAC-00000001",
            "party_id": None,
            "subtotal": "100.00",
            "tax": "16.00",
            "total": "116.00",
            "currency": "VES",
            "exchange_rate": "1.000000",
            "tax_rate": "16.00",
            "status": "posted",
            "created_by": "user-a",
            "created_at": "2026-09-18T14:00:00Z",
            "invoice_lines": [],
        }
    ]
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/pos/invoices")

    assert response.status_code == 200
    assert fake.captured_params["org_id"] == "eq.org-a"
    assert response.json()[0]["number"] == "FAC-00000001"

    app.dependency_overrides.clear()
