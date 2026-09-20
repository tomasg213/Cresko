from typing import Annotated

from fastapi import APIRouter, Depends

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    ArReceivable,
    BalanceOut,
    OrganizationContext,
    PaymentIn,
    Permission,
    SupplierPaymentIn,
)

router = APIRouter(prefix="/v1", tags=["finance"])


@router.get("/ap/invoices")
async def supplier_invoices(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    limit: int = 100,
) -> list[dict]:
    params: dict[str, str] = {
        "select": "id,number,total,currency,status",
        "org_id": f"eq.{context.org_id}",
        "status": "eq.posted",
        "order": "created_at.desc",
        "limit": str(min(max(limit, 1), 500)),
    }
    return await repository.get_json("supplier_invoices", params)


@router.get("/ar/balances", response_model=list[BalanceOut])
async def ar_balances(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    party_id: str | None = None,
) -> list[BalanceOut]:
    params: dict[str, str] = {"org_id": f"eq.{context.org_id}"}
    if party_id:
        params["party_id"] = f"eq.{party_id}"
    rows = await repository.get_json("ar_balances", params)
    return [BalanceOut.model_validate(row) for row in rows]


@router.get("/ar/receivables", response_model=list[ArReceivable])
async def ar_receivables(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    party_id: str | None = None,
) -> list[ArReceivable]:
    params: dict[str, str] = {"org_id": f"eq.{context.org_id}"}
    if party_id:
        params["party_id"] = f"eq.{party_id}"
    rows = await repository.get_json("ar_receivables", params)
    return [ArReceivable.model_validate(row) for row in rows]


@router.get("/ap/balances", response_model=list[BalanceOut])
async def ap_balances(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    party_id: str | None = None,
) -> list[BalanceOut]:
    params: dict[str, str] = {"org_id": f"eq.{context.org_id}"}
    if party_id:
        params["party_id"] = f"eq.{party_id}"
    rows = await repository.get_json("ap_balances", params)
    return [BalanceOut.model_validate(row) for row in rows]


@router.post("/ar/payments", status_code=201)
async def receive_payment(
    payload: PaymentIn,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.FINANCE_RECEIVE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> dict:
    return await repository.rpc(
        "cresko_receive_payment",
        {
            "p_org_id": context.org_id,
            "p_party_id": payload.party_id,
            "p_invoice_id": payload.invoice_id,
            "p_amount": str(payload.amount),
            "p_currency": payload.currency,
            "p_method": payload.method,
        },
    )


@router.post("/ap/payments", status_code=201)
async def pay_supplier(
    payload: SupplierPaymentIn,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.FINANCE_PAY)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> dict:
    return await repository.rpc(
        "cresko_pay_supplier",
        {
            "p_org_id": context.org_id,
            "p_supplier_invoice_id": payload.supplier_invoice_id,
            "p_amount": str(payload.amount),
            "p_currency": payload.currency,
            "p_method": payload.method,
        },
    )