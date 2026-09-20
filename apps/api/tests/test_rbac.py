from fastapi.testclient import TestClient
from helpers import context

from cresko_api.dependencies import get_current_membership, get_supabase_repository
from cresko_api.main import app


class _FakeRepository:
    def __init__(self) -> None:
        self.captured_rpc: tuple[str, dict] | None = None
        self.captured_params: dict[str, str] = {}
        self.rows: list[dict] = []

    async def get_json(self, resource: str, params: dict[str, str]) -> list[dict]:
        self.captured_params = params
        return self.rows

    async def post_json(self, resource: str, payload: dict, prefer: str | None = None) -> list[dict]:
        return [{**payload, "id": "new-1", "is_system": False, "created_at": "2026-09-18T17:00:00Z"}]

    async def rpc(self, function: str, payload: dict):
        self.captured_rpc = (function, payload)
        if function == "cresko_org_members":
            return [{"id": "m1", "org_id": "org-a", "user_id": "u1", "email": "a@x.com", "role_id": "r1", "role_name": "Cajero"}]
        return {"org_id": "org-a", "role_id": "r1"}


def test_create_role_requires_roles_manage() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["catalog.read"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post("/v1/roles", json={"name": "Cajero", "permissions": ["sales.checkout"]})

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_create_role_uses_org_and_permissions() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["roles.manage"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post("/v1/roles", json={"name": "Cajero", "permissions": ["sales.checkout", "sales.read"]})

    assert response.status_code == 201
    assert response.json()["name"] == "Cajero"
    assert fake.captured_params == {}

    app.dependency_overrides.clear()


def test_invite_member_requires_members_manage() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["catalog.read"])
    app.dependency_overrides[get_supabase_repository] = _FakeRepository
    client = TestClient(app)

    response = client.post("/v1/members/invitations", json={"email": "x@x.com", "role_id": "r1"})

    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_list_members_calls_rpc() -> None:
    app.dependency_overrides[get_current_membership] = lambda: context(["members.manage"])
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.get("/v1/members")

    assert response.status_code == 200
    assert fake.captured_rpc == ("cresko_org_members", {"p_org_id": "org-a"})
    assert response.json()[0]["email"] == "a@x.com"

    app.dependency_overrides.clear()


def test_accept_invitation_calls_rpc() -> None:
    fake = _FakeRepository()
    app.dependency_overrides[get_supabase_repository] = lambda: fake
    client = TestClient(app)

    response = client.post("/v1/members/invitations/accept", json={"token": "token-1"})

    assert response.status_code == 201
    assert fake.captured_rpc == ("cresko_accept_invitation", {"p_token": "token-1"})
    assert response.json() == {"accepted": True, "org_id": "org-a", "role_id": "r1"}

    app.dependency_overrides.clear()