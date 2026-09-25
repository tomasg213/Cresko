from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import OrganizationContext, OrganizationOut, OrganizationUpdate, Permission

router = APIRouter(prefix="/v1/orgs", tags=["orgs"])

_SELECT = "id,name,legal_name,tax_id,default_currency,timezone,access_status"


@router.get("", response_model=OrganizationOut)
async def get_organization(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> OrganizationOut:
    rows = await repository.get_json("organizations", {"select": _SELECT, "id": f"eq.{context.org_id}"})
    if not rows:
        raise HTTPException(status_code=404, detail="Organization not found")
    return OrganizationOut.model_validate(rows[0])


@router.patch("", response_model=OrganizationOut)
async def update_organization(
    payload: OrganizationUpdate,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.ORG_MANAGE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> OrganizationOut:
    body = payload.model_dump(mode="json", exclude_none=True)
    if not body:
        raise HTTPException(status_code=400, detail="Nothing to update")
    rows = await repository.patch_json(
        "organizations",
        body,
        {"id": f"eq.{context.org_id}", "select": _SELECT},
        prefer="return=representation",
    )
    if not rows:
        raise HTTPException(status_code=404, detail="Organization not found")
    return OrganizationOut.model_validate(rows[0])