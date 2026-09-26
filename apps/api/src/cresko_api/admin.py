from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from .config import Settings, get_settings
from .dependencies import get_current_membership, get_supabase_repository
from .preview import (
    _create_organization,
    _create_user,
    _provision_membership,
)
from .repositories import SupabaseRepository
from .schemas import AdminOrgOut, OrganizationContext

router = APIRouter(prefix="/v1/admin", tags=["admin"])


class AdminStatusUpdate(BaseModel):
    access_status: str | None = None
    payment_status: str | None = None
    notes: str | None = None


class AdminCreateOrgIn(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=320)
    password: str = Field(min_length=8, max_length=64)


class AdminCreateOrgOut(BaseModel):
    org_id: str
    org_name: str
    email: str


async def _require_portal_admin(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> None:
    is_admin = await repository.rpc("cresko_is_portal_admin", {})
    if is_admin is not True:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="administrator access denied",
        )


@router.get("/orgs", response_model=list[AdminOrgOut])
async def admin_list_orgs(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[AdminOrgOut]:
    # El RPC valida que el usuario sea administrador del portal.
    result = await repository.rpc("cresko_admin_list_orgs", {})
    return [AdminOrgOut.model_validate(row) for row in result]


@router.post(
    "/orgs",
    response_model=AdminCreateOrgOut,
    status_code=status.HTTP_201_CREATED,
)
async def admin_create_org(
    payload: AdminCreateOrgIn,
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AdminCreateOrgOut:
    await _require_portal_admin(context, repository)
    if not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Account provisioning is not configured",
        )

    email = payload.email.strip().lower()
    user_id = await _create_user(settings, email, payload.password)
    org_id = await _create_organization(
        settings,
        payload.name.strip(),
        user_id,
        is_demo=False,
    )
    await _provision_membership(settings, org_id, user_id)

    return AdminCreateOrgOut(
        org_id=org_id,
        org_name=payload.name.strip(),
        email=email,
    )


@router.post("/orgs/{target_org_id}/status")
async def admin_set_status(
    target_org_id: str,
    payload: AdminStatusUpdate,
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> dict:
    await _require_portal_admin(context, repository)
    await repository.rpc(
        "cresko_admin_set_status",
        {
            "p_org_id": target_org_id,
            "p_access_status": payload.access_status,
            "p_payment_status": payload.payment_status,
            "p_notes": payload.notes,
        },
    )
    return {"ok": True}