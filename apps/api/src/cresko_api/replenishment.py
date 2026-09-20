from typing import Annotated

from fastapi import APIRouter, Depends

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    OrganizationContext,
    Permission,
    ReplenishmentConfigIn,
    ReplenishmentItem,
)

router = APIRouter(prefix="/v1/replenishment", tags=["replenishment"])


@router.get("/needed", response_model=list[ReplenishmentItem])
async def replenishment_needed(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[ReplenishmentItem]:
    rows = await repository.rpc("cresko_replenishment_needed", {"p_org_id": context.org_id})
    return [ReplenishmentItem.model_validate(row) for row in rows]


@router.put("/config", status_code=204)
async def upsert_replenishment_config(
    payload: ReplenishmentConfigIn,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.REPLENISHMENT_WRITE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> None:
    body = payload.model_dump(mode="json")
    body["org_id"] = context.org_id
    body.pop("preferred_supplier_id", None)
    if payload.preferred_supplier_id:
        body["preferred_supplier_id"] = payload.preferred_supplier_id
    await repository.post_json("replenishment_config", body, prefer="resolution=merge-duplicates")