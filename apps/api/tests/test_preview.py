from fastapi.testclient import TestClient
from pydantic import ValidationError

from cresko_api.config import Settings, get_settings
from cresko_api.main import app


def test_settings_allows_missing_service_role() -> None:
    try:
        Settings(supabase_service_role_key=None)
    except ValidationError:
        raise AssertionError("service role key should be optional")
    assert Settings(supabase_service_role_key=None).supabase_service_role_key is None


def test_provision_returns_503_when_not_configured() -> None:
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://project.supabase.co",
        supabase_anon_key="anon-key",
        supabase_service_role_key=None,
    )
    client = TestClient(app)

    response = client.post("/v1/preview/provision", json={"name": "Tienda Demo"})

    assert response.status_code == 503

    app.dependency_overrides.clear()


def test_provision_validates_name_length() -> None:
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://project.supabase.co",
        supabase_anon_key="anon-key",
        supabase_service_role_key="service-role",
    )
    client = TestClient(app)

    response = client.post("/v1/preview/provision", json={"name": "A"})

    assert response.status_code == 422

    app.dependency_overrides.clear()