from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    AdjustmentIn,
    OrganizationContext,
    Permission,
    StockLevelOut,
    StockMovementOut,
    TransferIn,
    WarehouseCreateIn,
    WarehouseRef,
    WarehouseUpdateIn,
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


@router.post("/warehouses", response_model=WarehouseRef, status_code=201)
async def create_warehouse(
    payload: WarehouseCreateIn,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.ORG_MANAGE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> WarehouseRef:
    result = await repository.rpc(
        "cresko_create_warehouse",
        {
            "p_org_id": context.org_id,
            "p_name": payload.name,
            "p_code": payload.code,
        },
    )
    return WarehouseRef.model_validate(result)


@router.patch("/warehouses/{warehouse_id}", response_model=WarehouseRef)
async def update_warehouse(
    warehouse_id: str,
    payload: WarehouseUpdateIn,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.ORG_MANAGE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> WarehouseRef:
    body = payload.model_dump(mode="json", exclude_none=True)
    if not body:
        raise HTTPException(status_code=400, detail="Nothing to update")
    rows = await repository.patch_json(
        "warehouses",
        body,
        {"id": f"eq.{warehouse_id}", "org_id": f"eq.{context.org_id}", "select": "id,name,code"},
        prefer="return=representation",
    )
    if not rows:
        raise HTTPException(status_code=404, detail="Warehouse not found")
    return WarehouseRef.model_validate(rows[0])


@router.delete("/warehouses/{warehouse_id}", status_code=204)
async def delete_warehouse(
    warehouse_id: str,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.ORG_MANAGE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> None:
    # Soft-delete: se oculta de la app pero se conserva el histórico.
    rows = await repository.patch_json(
        "warehouses",
        {"is_active": False},
        {"id": f"eq.{warehouse_id}", "org_id": f"eq.{context.org_id}", "select": "id"},
        prefer="return=representation",
    )
    if not rows:
        raise HTTPException(status_code=404, detail="Warehouse not found")


@router.post("/transfers", status_code=204)
async def transfer_stock(
    payload: TransferIn,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.INVENTORY_WRITE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> None:
    await repository.rpc(
        "cresko_transfer_stock",
        {
            "p_org_id": context.org_id,
            "p_variant_id": payload.variant_id,
            "p_from_warehouse_id": payload.from_warehouse_id,
            "p_to_warehouse_id": payload.to_warehouse_id,
            "p_qty": str(payload.qty),
            "p_reason": payload.reason,
        },
    )


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