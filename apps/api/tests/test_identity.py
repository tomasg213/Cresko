from fastapi.testclient import TestClient

from cresko_api.auth import AuthenticatedUser
from cresko_api.dependencies import get_current_user, get_user_memberships
from cresko_api.main import app
from cresko_api.schemas import Membership


def _membership(org_id: str, name: str = "Administrador", permissions: list[str] | None = None) -> Membership:
    return Membership(
        org_id=org_id,
        role_id=f"role-{org_id}",
        role_name=name,
        permissions=permissions or [],
    )


def test_health_is_public() -> None:
    client = TestClient(app)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_context_requires_authentication() -> None:
    client = TestClient(app)

    response = client.get("/v1/context")

    assert response.status_code == 401


def test_user_can_only_select_an_existing_membership() -> None:
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(
        id="user-a", claims={}
    )
    app.dependency_overrides[get_user_memberships] = lambda: [
        _membership("org-a", permissions=["org.manage", "catalog.write"])
    ]
    client = TestClient(app)

    allowed = client.get("/v1/context", headers={"X-Org-ID": "org-a"})
    denied = client.get("/v1/context", headers={"X-Org-ID": "org-b"})

    assert allowed.status_code == 200
    body = allowed.json()
    assert body["org_id"] == "org-a"
    assert body["user_id"] == "user-a"
    assert body["role_name"] == "Administrador"
    assert "catalog.write" in body["permissions"]
    assert denied.status_code == 403

    app.dependency_overrides.clear()


def test_single_membership_can_be_selected_without_a_header() -> None:
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(
        id="user-a", claims={}
    )
    app.dependency_overrides[get_user_memberships] = lambda: [_membership("org-a")]
    client = TestClient(app)

    response = client.get("/v1/context")

    assert response.status_code == 200
    assert response.json()["org_id"] == "org-a"

    app.dependency_overrides.clear()