from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app
from cresko_api.schemas import OrganizationContext


class _FakeRepository:
    def __init__(self) -> None:
        self.captured: dict[str, str] = {}
        self.captured_rpc: tuple[str, dict] | None = None

    async def get_json(self, resource: str, params: dict[str, str]) -> list[dict]:
        self.captured = params
        return []

    async def rpc(self, function: str, payload: dict) -> dict:
        self.captured_rpc = (function, payload)
        return {
            "id": "product-1",
            "org_id": "org-a",
            "name": payload.get("p_name", "product-1"),
            "category_id": None,
            "brand_id": None,
            "base_unit": payload.get("p_base_unit") or "unit",
            "is_active": True,
            "product_variants": [],
        }


def _admin_context() -> OrganizationContext:
    return context(["catalog.write"])


def _cashier_context() -> OrganizationContext:
    return context(["catalog.read"])


def test_create_product_requires_admin() -> None:
    app.dependency_overrides[get_current_membership] = _cashier_context
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post(
        "/v1/catalog/products",
        json={"name": "Camisa", "variants": [{"sku": "CM-AZ-M", "name": "Azul / M"}]},
    )

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_create_product_calls_rpc_with_prefixed_params() -> None:
    app.dependency_overrides[get_current_membership] = _admin_context
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/catalog/products",
        json={
            "name": "Camisa",
            "description": "Algodón",
            "base_unit": "unit",
            "variants": [
                {
                    "sku": "CM-AZ-M",
                    "barcodes": [{"barcode": "7790000000001"}],
                    "prices": [{"price_list_code": "retail", "currency": "VES", "amount": 50}],
                }
            ],
        },
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_create_product"
    assert set(payload.keys()) == {
        "p_org_id",
        "p_name",
        "p_variants",
        "p_category_id",
        "p_brand_id",
        "p_base_unit",
        "p_description",
        "p_is_taxable",
    }
    assert payload["p_org_id"] == "org-a"
    assert payload["p_name"] == "Camisa"
    assert payload["p_base_unit"] == "unit"

    app.dependency_overrides.clear()


def test_list_products_is_scoped_to_org() -> None:
    app.dependency_overrides[get_current_membership] = _admin_context
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/catalog/products")

    assert response.status_code == 200
    assert response.json() == []
    assert fake.captured["org_id"] == "eq.org-a"

    app.dependency_overrides.clear()


def test_product_requires_at_least_one_variant() -> None:
    app.dependency_overrides[get_current_membership] = _admin_context
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post("/v1/catalog/products", json={"name": "Camisa", "variants": []})

    assert response.status_code == 422

    app.dependency_overrides.clear()


def test_negative_price_is_rejected() -> None:
    app.dependency_overrides[get_current_membership] = _admin_context
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/catalog/products",
        json={
            "name": "Camisa",
            "variants": [
                {
                    "sku": "CM-AZ-M",
                    "prices": [{"price_list_code": "retail", "amount": -1}],
                }
            ],
        },
    )

    assert response.status_code == 422

    app.dependency_overrides.clear()


def test_prices_are_registered_in_usd() -> None:
    app.dependency_overrides[get_current_membership] = _admin_context
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post(
        "/v1/catalog/products",
        json={
            "name": "Camisa",
            "variants": [
                {
                    "sku": "CM-AZ-M",
                    "prices": [{"price_list_code": "retail", "amount": 10}],
                }
            ],
        },
    )

    assert response.status_code == 201
    function, payload = fake.captured_rpc
    assert function == "cresko_create_product"
    price = payload["p_variants"][0]["prices"][0]
    assert price == {"price_list_code": "retail", "amount": "10"}

    app.dependency_overrides.clear()


def test_update_product_requires_catalog_write() -> None:
    app.dependency_overrides[get_current_membership] = _cashier_context
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.patch("/v1/catalog/products/prod-1", json={"name": "Nuevo"})

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_update_product_calls_rpc_with_prefixed_params() -> None:
    app.dependency_overrides[get_current_membership] = _admin_context
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.patch(
        "/v1/catalog/products/prod-1",
        json={
            "name": "Camisa Renovada",
            "variants": [
                {
                    "variant_id": "v1",
                    "name": "Azul / M",
                    "prices": [{"price_list_code": "retail", "amount": 12}],
                }
            ],
        },
    )

    assert response.status_code == 200
    function, payload = fake.captured_rpc
    assert function == "cresko_update_product"
    assert payload["p_product_id"] == "prod-1"
    assert payload["p_name"] == "Camisa Renovada"
    assert payload["p_variants"][0]["variant_id"] == "v1"

    app.dependency_overrides.clear()


def test_delete_product_requires_catalog_write() -> None:
    app.dependency_overrides[get_current_membership] = _cashier_context
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.delete("/v1/catalog/products/prod-1")

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_delete_product_calls_rpc_with_org() -> None:
    app.dependency_overrides[get_current_membership] = _admin_context
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.delete("/v1/catalog/products/prod-1")

    assert response.status_code == 204
    function, payload = fake.captured_rpc
    assert function == "cresko_delete_product"
    assert payload == {"p_org_id": "org-a", "p_product_id": "prod-1"}

    app.dependency_overrides.clear()
