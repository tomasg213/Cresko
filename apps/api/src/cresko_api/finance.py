from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    ApPaymentOut,
    ApReceivable,
    ArPaymentOut,
    ArReceivable,
    BalanceOut,
    GeneralPaymentIn,
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


@router.get("/ap/receivables", response_model=list[ApReceivable])
async def ap_receivables(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    party_id: str | None = None,
) -> list[ApReceivable]:
    params: dict[str, str] = {"org_id": f"eq.{context.org_id}"}
    if party_id:
        params["party_id"] = f"eq.{party_id}"
    rows = await repository.get_json("ap_receivables", params)
    return [ApReceivable.model_validate(row) for row in rows]


@router.get("/ar/payments", response_model=list[ArPaymentOut])
async def ar_payments(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    invoice_id: str | None = None,
) -> list[ArPaymentOut]:
    params: dict[str, str] = {
        "select": "id,amount,currency,method,status,created_at,invoice_id,"
        "invoice:invoices(number,party:parties(name))",
        "org_id": f"eq.{context.org_id}",
        "order": "created_at.desc",
    }
    if invoice_id:
        params["invoice_id"] = f"eq.{invoice_id}"
    rows = await repository.get_json("payments", params)
    result: list[ArPaymentOut] = []
    for row in rows:
        invoice = row.pop("invoice", {}) or {}
        party = invoice.pop("party", {}) or {}
        result.append(
            ArPaymentOut(
                id=row["id"],
                invoice_id=row["invoice_id"],
                invoice_number=invoice.get("number"),
                party_name=party.get("name"),
                amount=row["amount"],
                currency=row["currency"],
                method=row["method"],
                status=row["status"],
                created_at=row["created_at"],
            )
        )
    return result


@router.post("/ar/payments/{payment_id}/void", status_code=status.HTTP_204_NO_CONTENT)
async def void_payment(
    payment_id: str,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.FINANCE_RECEIVE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> Response:
    await repository.rpc("cresko_void_payment", {"p_org_id": context.org_id, "p_payment_id": payment_id})
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/ap/payments", response_model=list[ApPaymentOut])
async def ap_payments(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[ApPaymentOut]:
    params: dict[str, str] = {
        "select": "id,amount,currency,created_at,supplier_invoice_id,"
        "supplier_invoice:supplier_invoices(id,number,supplier_id,party:parties(name))",
        "org_id": f"eq.{context.org_id}",
        "entry_type": "eq.payment",
        "order": "created_at.desc",
    }
    rows = await repository.get_json("ap_ledger", params)
    result: list[ApPaymentOut] = []
    for row in rows:
        invoice = row.pop("supplier_invoice", {}) or {}
        party = invoice.pop("party", {}) or {}
        result.append(
            ApPaymentOut(
                id=row["id"],
                supplier_invoice_id=row["supplier_invoice_id"],
                invoice_number=invoice.get("number"),
                supplier_name=party.get("name"),
                amount=row["amount"],
                currency=row["currency"],
                created_at=row["created_at"],
            )
        )
    return result


@router.post("/ap/payments/{ledger_id}/void", status_code=status.HTTP_204_NO_CONTENT)
async def void_ap_payment(
    ledger_id: str,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.FINANCE_PAY)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> Response:
    await repository.rpc(
        "cresko_void_ap_payment",
        {"p_org_id": context.org_id, "p_ledger_id": ledger_id},
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


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


@router.post("/ar/payments/general", status_code=201)
async def receive_general_payment(
    payload: GeneralPaymentIn,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.FINANCE_RECEIVE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[dict]:
    return await repository.rpc(
        "cresko_apply_ar_payment",
        {
            "p_org_id": context.org_id,
            "p_party_id": payload.party_id,
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


@router.post("/ap/payments/general", status_code=201)
async def pay_supplier_general(
    payload: GeneralPaymentIn,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.FINANCE_PAY)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[dict]:
    return await repository.rpc(
        "cresko_apply_ap_payment",
        {
            "p_org_id": context.org_id,
            "p_party_id": payload.party_id,
            "p_amount": str(payload.amount),
            "p_currency": payload.currency,
            "p_method": payload.method,
        },
    )