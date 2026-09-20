from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    OrganizationContext,
    Permission,
    ReplenishmentConfigIn,
    ReplenishmentConfigOut,
    ReplenishmentConfigUpdate,
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


@router.get("/configs", response_model=list[ReplenishmentConfigOut])
async def list_replenishment_configs(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[ReplenishmentConfigOut]:
    params: dict[str, str] = {
        "select": "*,variant:product_variants(id,name,sku),warehouse:warehouses(id,name,code)",
        "org_id": f"eq.{context.org_id}",
        "order": "created_at.desc",
    }
    rows = await repository.get_json("replenishment_config", params)
    return [ReplenishmentConfigOut.model_validate(row) for row in rows]


@router.put("/config", status_code=status.HTTP_204_NO_CONTENT)
async def upsert_replenishment_config(
    payload: ReplenishmentConfigIn,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.REPLENISHMENT_WRITE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> Response:
    body = payload.model_dump(mode="json")
    body["org_id"] = context.org_id
    body.pop("preferred_supplier_id", None)
    if payload.preferred_supplier_id:
        body["preferred_supplier_id"] = payload.preferred_supplier_id
    await repository.post_json("replenishment_config", body, prefer="resolution=merge-duplicates")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.patch("/config/{config_id}", response_model=ReplenishmentConfigOut)
async def update_replenishment_config(
    config_id: str,
    payload: ReplenishmentConfigUpdate,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.REPLENISHMENT_WRITE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> ReplenishmentConfigOut:
    body = payload.model_dump(mode="json", exclude_unset=True)
    params: dict[str, str] = {"org_id": f"eq.{context.org_id}", "id": f"eq.{config_id}"}
    rows = await repository.patch_json("replenishment_config", body, params, prefer="return=representation")
    if not rows:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Replenishment config not found")
    return ReplenishmentConfigOut.model_validate(rows[0])


@router.delete("/config/{config_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_replenishment_config(
    config_id: str,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.REPLENISHMENT_WRITE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> Response:
    params: dict[str, str] = {"org_id": f"eq.{context.org_id}", "id": f"eq.{config_id}"}
    await repository.delete_json("replenishment_config", params)
    return Response(status_code=status.HTTP_204_NO_CONTENT)