from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app


class _FakeRepository:
    def __init__(self) -> None:
        self.captured_rpc: tuple[str, dict] | None = None

    async def rpc(self, function: str, payload: dict):
        self.captured_rpc = (function, payload)
        if function == "cresko_export_org":
            return {"version": 1, "products": []}
        return "Respaldo restaurado correctamente (0 registros)."


def test_export_requires_org_manage() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["catalog.read"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.get("/v1/backup/export")

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_export_calls_rpc_with_org() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["org.manage"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/backup/export")

    assert response.status_code == 200
    assert fake.captured_rpc == ("cresko_export_org", {"p_org_id": "org-a"})
    assert response.json()["version"] == 1

    app.dependency_overrides.clear()


def test_import_requires_org_manage() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["catalog.read"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post("/v1/backup/import", json={"data": {"version": 1}})

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_import_calls_rpc_with_data() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["org.manage"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    payload = {"data": {"version": 1, "products": []}}
    response = client.post("/v1/backup/import", json=payload)

    assert response.status_code == 200
    function, rpc_payload = fake.captured_rpc
    assert function == "cresko_import_org"
    assert rpc_payload["p_org_id"] == "org-a"
    assert rpc_payload["p_data"]["version"] == 1
    assert "restaurado" in response.json()["message"]

    app.dependency_overrides.clear()