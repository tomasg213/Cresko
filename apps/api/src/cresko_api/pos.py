from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    CheckoutIn,
    InvoiceOut,
    OrganizationContext,
    PartyOut,
    Permission,
    PosCustomerCreate,
)

router = APIRouter(prefix="/v1/pos", tags=["pos"])

_INVOICE_SELECT = (
    "*,party:parties(id,name,document_type,document_id),"
    "invoice_lines(*,variant:product_variants(id,name,sku))"
)


@router.post("/customers", response_model=PartyOut, status_code=201)
async def create_customer(
    payload: PosCustomerCreate,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.SALES_CHECKOUT)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> PartyOut:
    result = await repository.rpc(
        "cresko_create_customer",
        {
            "p_org_id": context.org_id,
            "p_name": payload.name,
            "p_document_type": payload.document_type,
            "p_document_id": payload.document_id,
            "p_phone": payload.phone,
            "p_email": payload.email,
        },
    )
    return PartyOut.model_validate(result)


@router.post("/checkout", response_model=InvoiceOut, status_code=201)
async def checkout(
    payload: CheckoutIn,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.SALES_CHECKOUT)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> InvoiceOut:
    rate = await repository.rpc("cresko_current_exchange_rate", {"p_org_id": context.org_id})
    if rate is None:
        raise HTTPException(status_code=400, detail="No hay tasa de cambio configurada para hoy")

    result = await repository.rpc(
        "cresko_checkout",
        {
            "p_org_id": context.org_id,
            "p_warehouse_id": payload.warehouse_id,
            "p_price_list_code": payload.price_list_code,
            "p_exchange_rate": str(rate),
            "p_tax_rate": str(payload.tax_rate),
            "p_lines": [line.model_dump(mode="json") for line in payload.lines],
            "p_payment_method": payload.payment_method,
            "p_paid_amount": str(payload.paid_amount),
            "p_party_id": payload.party_id,
            "p_party": payload.party.model_dump(mode="json") if payload.party else None,
        },
    )
    return InvoiceOut.model_validate(result)


@router.get("/invoices", response_model=list[InvoiceOut])
async def list_invoices(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    limit: int = 100,
) -> list[InvoiceOut]:
    params: dict[str, str] = {
        "select": _INVOICE_SELECT,
        "org_id": f"eq.{context.org_id}",
        "order": "created_at.desc",
        "limit": str(min(max(limit, 1), 500)),
    }
    rows = await repository.get_json("invoices", params)
    return [InvoiceOut.model_validate(row) for row in rows]


@router.get("/invoices/{invoice_id}", response_model=InvoiceOut)
async def get_invoice(
    invoice_id: str,
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> InvoiceOut:
    params: dict[str, str] = {
        "select": _INVOICE_SELECT,
        "org_id": f"eq.{context.org_id}",
        "id": f"eq.{invoice_id}",
    }
    rows = await repository.get_json("invoices", params)
    if not rows:
        raise HTTPException(status_code=404, detail="Invoice not found")
    return InvoiceOut.model_validate(rows[0])