from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    GoodsReceiptCreate,
    GoodsReceiptOut,
    OrganizationContext,
    Permission,
    PurchaseOrderCreate,
    PurchaseOrderOut,
)

router = APIRouter(prefix="/v1/purchasing", tags=["purchasing"])

_ORDER_SELECT = "*,po_lines(*,variant:product_variants(id,name,sku))"
_RECEIPT_SELECT = "*,po:purchase_orders(id,number,supplier_id)"


@router.post("/orders", response_model=PurchaseOrderOut, status_code=201)
async def create_purchase_order(
    payload: PurchaseOrderCreate,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.PURCHASING_WRITE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> PurchaseOrderOut:
    result = await repository.rpc(
        "cresko_create_purchase_order",
        {
            "p_org_id": context.org_id,
            "p_supplier_id": payload.supplier_id,
            "p_warehouse_id": payload.warehouse_id,
            "p_currency": payload.currency,
            "p_exchange_rate": str(payload.exchange_rate),
            "p_tax_rate": str(payload.tax_rate),
            "p_lines": [line.model_dump(mode="json") for line in payload.lines],
            "p_expected_at": payload.expected_at,
            "p_notes": payload.notes,
        },
    )
    return PurchaseOrderOut.model_validate(result)


@router.patch("/orders/{order_id}", response_model=PurchaseOrderOut)
async def update_purchase_order(
    order_id: str,
    payload: PurchaseOrderCreate,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.PURCHASING_WRITE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> PurchaseOrderOut:
    result = await repository.rpc(
        "cresko_update_purchase_order",
        {
            "p_org_id": context.org_id,
            "p_po_id": order_id,
            "p_supplier_id": payload.supplier_id,
            "p_warehouse_id": payload.warehouse_id,
            "p_currency": payload.currency,
            "p_exchange_rate": str(payload.exchange_rate),
            "p_tax_rate": str(payload.tax_rate),
            "p_lines": [line.model_dump(mode="json") for line in payload.lines],
            "p_expected_at": payload.expected_at,
            "p_notes": payload.notes,
        },
    )
    return PurchaseOrderOut.model_validate(result)


@router.delete("/orders/{order_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_purchase_order(
    order_id: str,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.PURCHASING_WRITE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> Response:
    await repository.rpc(
        "cresko_delete_purchase_order",
        {"p_org_id": context.org_id, "p_po_id": order_id},
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/orders", response_model=list[PurchaseOrderOut])
async def list_purchase_orders(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    limit: int = 100,
) -> list[PurchaseOrderOut]:
    params: dict[str, str] = {
        "select": _ORDER_SELECT,
        "org_id": f"eq.{context.org_id}",
        "order": "created_at.desc",
        "limit": str(min(max(limit, 1), 500)),
    }
    rows = await repository.get_json("purchase_orders", params)
    return [PurchaseOrderOut.model_validate(row) for row in rows]


@router.get("/orders/{order_id}", response_model=PurchaseOrderOut)
async def get_purchase_order(
    order_id: str,
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> PurchaseOrderOut:
    params: dict[str, str] = {
        "select": _ORDER_SELECT,
        "org_id": f"eq.{context.org_id}",
        "id": f"eq.{order_id}",
    }
    rows = await repository.get_json("purchase_orders", params)
    if not rows:
        raise HTTPException(status_code=404, detail="Purchase order not found")
    return PurchaseOrderOut.model_validate(rows[0])


@router.post("/orders/{order_id}/receive", response_model=GoodsReceiptOut, status_code=201)
async def receive_goods(
    order_id: str,
    payload: GoodsReceiptCreate,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.PURCHASING_RECEIVE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> GoodsReceiptOut:
    result = await repository.rpc(
        "cresko_receive_goods",
        {
            "p_org_id": context.org_id,
            "p_po_id": order_id,
            "p_lines": [line.model_dump(mode="json") for line in payload.lines],
            "p_received_at": payload.received_at,
            "p_notes": payload.notes,
        },
    )
    return GoodsReceiptOut.model_validate(result)


@router.get("/receipts", response_model=list[GoodsReceiptOut])
async def list_receipts(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    limit: int = 100,
) -> list[GoodsReceiptOut]:
    params: dict[str, str] = {
        "select": _RECEIPT_SELECT,
        "org_id": f"eq.{context.org_id}",
        "order": "created_at.desc",
        "limit": str(min(max(limit, 1), 500)),
    }
    rows = await repository.get_json("goods_receipts", params)
    return [GoodsReceiptOut.model_validate(row) for row in rows]