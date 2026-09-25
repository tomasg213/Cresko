import secrets
import string
from typing import Annotated

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from .config import Settings, get_settings

router = APIRouter(prefix="/v1/preview", tags=["preview"])

BUSINESS_TYPES = ("abasto", "licoreria", "ropa", "carniceria", "verduleria")


class PreviewProvisionIn(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=80)
    business: str | None = Field(default=None, max_length=20)
    email: str | None = Field(default=None, max_length=320)
    password: str | None = Field(default=None, min_length=8, max_length=64)


class PreviewProvisionOut(BaseModel):
    email: str
    password: str
    org_id: str
    org_name: str
    business: str


def _generate_email() -> str:
    token = "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(8))
    return f"demo-{token}@cresko.preview"


def _generate_password() -> str:
    return "Demo-" + "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(10))


def _slug(name: str) -> str:
    cleaned = "".join(ch if ch.isalnum() or ch == " " else " " for ch in name)
    words = [w for w in cleaned.split() if w]
    return " ".join(words[:4]) or "Comercio Demo"


@router.post("/provision", response_model=PreviewProvisionOut, status_code=status.HTTP_201_CREATED)
async def provision_preview(
    payload: PreviewProvisionIn,
    settings: Annotated[Settings, Depends(get_settings)],
) -> PreviewProvisionOut:
    if not settings.supabase_service_role_key:
        raise HTTPException(status_code=503, detail="Preview provisioning is not configured")

    org_name = _slug(payload.name) if payload.name else "Comercio Demo"
    business = payload.business if payload.business in BUSINESS_TYPES else "abasto"
    email = (payload.email or _generate_email()).strip().lower()
    password = payload.password or _generate_password()

    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
    }

    # 1. Crear usuario confirmado en Supabase Auth (service role).
    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.post(
            f"{settings.auth_url}/admin/users",
            headers=headers,
            json={"email": email, "password": password, "email_confirm": True},
        )
    if response.status_code >= 400:
        raise HTTPException(status_code=400, detail=f"No se pudo crear la cuenta demo: {response.text[:200]}")

    user = response.json()
    user_id = user.get("id")
    if not user_id:
        raise HTTPException(status_code=502, detail="No se pudo crear la cuenta demo")

    # 2. Crear la organización (service role, evita RLS).
    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.post(
            f"{settings.rest_url}/organizations",
            headers={**headers, "Prefer": "return=representation"},
            params={"select": "id,name"},
            json={"name": org_name, "legal_name": org_name, "default_currency": "VES", "created_by": user_id},
        )
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"No se pudo crear la organización: {response.text[:200]}")
    org = response.json()
    org_id = org[0]["id"] if isinstance(org, list) else org["id"]

    # 3. Rol administrador con todos los permisos.
    async with httpx.AsyncClient(timeout=20.0) as client:
        permissions_response = await client.get(
            f"{settings.rest_url}/permissions",
            headers=headers,
            params={"select": "code"},
        )
    permissions = [row["code"] for row in permissions_response.json()] if permissions_response.status_code < 400 else []

    async with httpx.AsyncClient(timeout=20.0) as client:
        role_response = await client.post(
            f"{settings.rest_url}/org_roles",
            headers={**headers, "Prefer": "return=representation"},
            params={"select": "id"},
            json={"org_id": org_id, "name": "Administrador", "permissions": permissions, "is_system": True},
        )
    if role_response.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"No se pudo crear el rol: {role_response.text[:200]}")
    role_id = role_response.json()[0]["id"]

    # 4. Membresía del usuario.
    async with httpx.AsyncClient(timeout=20.0) as client:
        membership_response = await client.post(
            f"{settings.rest_url}/memberships",
            headers=headers,
            json={"org_id": org_id, "user_id": user_id, "role_id": role_id},
        )
    if membership_response.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"No se pudo crear la membresía: {membership_response.text[:200]}")

    # 5. Sembrar datos mock según el tipo de negocio.
    async with httpx.AsyncClient(timeout=60.0) as client:
        seed_response = await client.post(
            f"{settings.rest_url}/rpc/cresko_setup_demo",
            headers=headers,
            json={"p_org_id": org_id, "p_user_id": user_id, "p_business": business},
        )
    if seed_response.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"No se pudo sembrar la demo: {seed_response.text[:200]}")

    return PreviewProvisionOut(email=email, password=password, org_id=org_id, org_name=org_name, business=business)