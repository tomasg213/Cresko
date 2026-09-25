from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    OrderCreate,
    OrderOut,
    OrderPaymentIn,
    OrderPaymentOut,
    OrderReceivable,
    OrganizationContext,
    Permission,
    SpecialOrderProductCreate,
    SpecialOrderProductOut,
    SpecialOrderProductUpdate,
)

router = APIRouter(prefix="/v1/orders", tags=["orders"])

_ORDER_SELECT = (
    "*,party:parties(id,name,document_type,document_id),"
    "product:special_order_products(id,org_id,variant_id,unit_price,currency,is_active,created_by,created_at,"
    "variant:product_variants(id,name,sku))"
)

_PRODUCT_SELECT = (
    "id,org_id,variant_id,unit_price,currency,is_active,created_by,created_at,"
    "variant:product_variants(id,name,sku)"
)


# =====================================================================
# Productos bajo pedido
# =====================================================================

@router.get("/products", response_model=list[SpecialOrderProductOut])
async def list_special_products(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[SpecialOrderProductOut]:
    params: dict[str, str] = {
        "select": _PRODUCT_SELECT,
        "org_id": f"eq.{context.org_id}",
        "order": "name.asc",
    }
    rows = await repository.get_json("special_order_products", params)
    return [SpecialOrderProductOut.model_validate(row) for row in rows]


@router.post("/products", response_model=SpecialOrderProductOut, status_code=201)
async def create_special_product(
    payload: SpecialOrderProductCreate,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.CATALOG_WRITE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> SpecialOrderProductOut:
    result = await repository.rpc(
        "cresko_create_special_product",
        {
            "p_org_id": context.org_id,
            "p_variant_id": payload.variant_id,
            "p_unit_price": str(payload.unit_price) if payload.unit_price is not None else None,
            "p_currency": payload.currency,
        },
    )
    return SpecialOrderProductOut.model_validate(result)


@router.patch("/products/{product_id}", response_model=SpecialOrderProductOut)
async def update_special_product(
    product_id: str,
    payload: SpecialOrderProductUpdate,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.CATALOG_WRITE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> SpecialOrderProductOut:
    body = payload.model_dump(mode="json", exclude_unset=True)
    params: dict[str, str] = {
        "org_id": f"eq.{context.org_id}",
        "id": f"eq.{product_id}",
        "select": _PRODUCT_SELECT,
    }
    rows = await repository.patch_json("special_order_products", body, params, prefer="return=representation")
    if not rows:
        raise HTTPException(status_code=404, detail="Product under order not found")
    return SpecialOrderProductOut.model_validate(rows[0])


# =====================================================================
# Pedidos
# =====================================================================

@router.get("", response_model=list[OrderOut])
async def list_orders(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    product_id: str | None = None,
    limit: int = 100,
) -> list[OrderOut]:
    params: dict[str, str] = {
        "select": _ORDER_SELECT,
        "org_id": f"eq.{context.org_id}",
        "order": "created_at.desc",
        "limit": str(min(max(limit, 1), 500)),
    }
    if product_id:
        params["product_id"] = f"eq.{product_id}"
    rows = await repository.get_json("orders", params)
    return [OrderOut.model_validate(row) for row in rows]


@router.get("/receivables", response_model=list[OrderReceivable])
async def order_receivables(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[OrderReceivable]:
    params: dict[str, str] = {
        "org_id": f"eq.{context.org_id}",
        "order": "created_at.desc",
    }
    rows = await repository.get_json("order_receivables", params)
    return [OrderReceivable.model_validate(row) for row in rows]


@router.get("/{order_id}", response_model=OrderOut)
async def get_order(
    order_id: str,
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> OrderOut:
    params: dict[str, str] = {
        "select": _ORDER_SELECT,
        "org_id": f"eq.{context.org_id}",
        "id": f"eq.{order_id}",
    }
    rows = await repository.get_json("orders", params)
    if not rows:
        raise HTTPException(status_code=404, detail="Order not found")
    return OrderOut.model_validate(rows[0])


@router.post("", response_model=OrderOut, status_code=201)
async def create_order(
    payload: OrderCreate,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.SALES_CHECKOUT)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> OrderOut:
    result = await repository.rpc(
        "cresko_create_order",
        {
            "p_org_id": context.org_id,
            "p_product_id": payload.product_id,
            "p_party_id": payload.party_id,
            "p_qty": str(payload.qty),
            "p_unit_price": str(payload.unit_price),
            "p_currency": payload.currency,
            "p_exchange_rate": str(payload.exchange_rate),
            "p_tax_rate": str(payload.tax_rate),
            "p_paid_amount": str(payload.paid_amount),
            "p_payment_method": payload.payment_method,
            "p_expected_at": payload.expected_at,
            "p_notes": payload.notes,
        },
    )
    return OrderOut.model_validate(result)


@router.post("/{order_id}/pay", response_model=OrderOut)
async def pay_order(
    order_id: str,
    payload: OrderPaymentIn,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.FINANCE_RECEIVE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> OrderOut:
    result = await repository.rpc(
        "cresko_pay_order",
        {
            "p_org_id": context.org_id,
            "p_order_id": order_id,
            "p_amount": str(payload.amount),
            "p_method": payload.method,
        },
    )
    return OrderOut.model_validate(result)


@router.post("/{order_id}/cancel", response_model=OrderOut)
async def cancel_order(
    order_id: str,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.SALES_CHECKOUT)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> OrderOut:
    result = await repository.rpc(
        "cresko_cancel_order",
        {"p_org_id": context.org_id, "p_order_id": order_id},
    )
    return OrderOut.model_validate(result)


@router.get("/{order_id}/payments", response_model=list[OrderPaymentOut])
async def order_payments(
    order_id: str,
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[OrderPaymentOut]:
    params: dict[str, str] = {
        "select": "id,order_id,amount,currency,method,created_at",
        "org_id": f"eq.{context.org_id}",
        "order_id": f"eq.{order_id}",
        "order": "created_at.desc",
    }
    rows = await repository.get_json("order_payments", params)
    return [OrderPaymentOut.model_validate(row) for row in rows]


@router.delete("/{order_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_order(
    order_id: str,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.SALES_CHECKOUT)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> Response:
    await repository.rpc(
        "cresko_cancel_order",
        {"p_org_id": context.org_id, "p_order_id": order_id},
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)