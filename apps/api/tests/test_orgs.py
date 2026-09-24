from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app


class _FakeRepository:
    def __init__(self) -> None:
        self.org = {
            "id": "org-a",
            "name": "Mi Comercio",
            "legal_name": None,
            "tax_id": None,
            "default_currency": "VES",
            "timezone": "America/Caracas",
        }
        self.captured_patch: tuple[dict, dict] | None = None

    async def get_json(self, resource: str, params: dict[str, str]) -> list[dict]:
        return [self.org]

    async def patch_json(
        self,
        resource: str,
        payload: dict,
        params: dict[str, str],
        prefer: str | None = None,
    ) -> list[dict]:
        self.captured_patch = (payload, params)
        self.org = {**self.org, **payload}
        return [self.org]


def test_get_org_returns_current() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["catalog.read"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/orgs")

    assert response.status_code == 200
    assert response.json()["name"] == "Mi Comercio"
    assert fake.captured_patch is None

    app.dependency_overrides.clear()


def test_update_org_requires_org_manage() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["catalog.read"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.patch("/v1/orgs", json={"name": "Nuevo Nombre"})

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_update_org_applies_changes_to_current_org() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["org.manage"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.patch("/v1/orgs", json={"name": "Ferretería Central", "tax_id": "J-12345678-9"})

    assert response.status_code == 200
    assert response.json()["name"] == "Ferretería Central"
    payload, params = fake.captured_patch
    assert payload["name"] == "Ferretería Central"
    assert params["id"] == "eq.org-a"

    app.dependency_overrides.clear()


def test_update_org_normalizes_tax_id_as_rif() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["org.manage"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.patch("/v1/orgs", json={"tax_id": "123456789"})

    assert response.status_code == 200
    payload, _ = fake.captured_patch
    assert payload["tax_id"] == "J-12345678-9"

    app.dependency_overrides.clear()