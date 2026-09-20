from typing import Annotated

from fastapi import APIRouter, Depends

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    AdjustmentIn,
    OrganizationContext,
    Permission,
    StockLevelOut,
    StockMovementOut,
    WarehouseRef,
)

router = APIRouter(prefix="/v1/inventory", tags=["inventory"])

_STOCK_SELECT = "*,variant:product_variants(id,name,sku),warehouse:warehouses(id,name,code)"
_MOVEMENT_SELECT = "*,variant:product_variants(id,name,sku),warehouse:warehouses(id,name,code)"


@router.get("/warehouses", response_model=list[WarehouseRef])
async def list_warehouses(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[WarehouseRef]:
    rows = await repository.get_json(
        "warehouses",
        {"select": "id,name,code", "org_id": f"eq.{context.org_id}", "is_active": "eq.true"},
    )
    return [WarehouseRef.model_validate(row) for row in rows]


@router.get("/stock", response_model=list[StockLevelOut])
async def list_stock(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    variant_id: str | None = None,
    warehouse_id: str | None = None,
) -> list[StockLevelOut]:
    params: dict[str, str] = {
        "select": _STOCK_SELECT,
        "org_id": f"eq.{context.org_id}",
        "order": "updated_at.desc",
    }
    if variant_id:
        params["variant_id"] = f"eq.{variant_id}"
    if warehouse_id:
        params["warehouse_id"] = f"eq.{warehouse_id}"

    rows = await repository.get_json("stock_levels", params)
    return [StockLevelOut.model_validate(row) for row in rows]


@router.get("/movements", response_model=list[StockMovementOut])
async def list_movements(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    variant_id: str | None = None,
    warehouse_id: str | None = None,
    limit: int = 100,
) -> list[StockMovementOut]:
    params: dict[str, str] = {
        "select": _MOVEMENT_SELECT,
        "org_id": f"eq.{context.org_id}",
        "order": "created_at.desc",
        "limit": str(min(max(limit, 1), 500)),
    }
    if variant_id:
        params["variant_id"] = f"eq.{variant_id}"
    if warehouse_id:
        params["warehouse_id"] = f"eq.{warehouse_id}"

    rows = await repository.get_json("stock_movements", params)
    return [StockMovementOut.model_validate(row) for row in rows]


@router.post("/adjustments", response_model=StockMovementOut, status_code=201)
async def adjust_stock(
    payload: AdjustmentIn,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.INVENTORY_WRITE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> StockMovementOut:
    result = await repository.rpc(
        "cresko_adjust_stock",
        {
            "p_org_id": context.org_id,
            "p_variant_id": payload.variant_id,
            "p_warehouse_id": payload.warehouse_id,
            "p_delta": str(payload.delta),
            "p_reason": payload.reason,
        },
    )
    return StockMovementOut.model_validate(result)