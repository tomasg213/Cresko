from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from .dependencies import get_current_membership, get_supabase_repository
from .repositories import SupabaseRepository
from .schemas import AdminOrgOut, OrganizationContext

router = APIRouter(prefix="/v1/admin", tags=["admin"])


class AdminStatusUpdate(BaseModel):
    access_status: str | None = None
    payment_status: str | None = None
    notes: str | None = None


@router.get("/orgs", response_model=list[AdminOrgOut])
async def admin_list_orgs(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[AdminOrgOut]:
    # El RPC valida que el usuario sea administrador del portal.
    result = await repository.rpc("cresko_admin_list_orgs", {})
    return [AdminOrgOut.model_validate(row) for row in result]


@router.post("/orgs/{target_org_id}/status")
async def admin_set_status(
    target_org_id: str,
    payload: AdminStatusUpdate,
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> dict:
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