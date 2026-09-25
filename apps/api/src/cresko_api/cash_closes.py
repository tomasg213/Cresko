from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    CashCloseOut,
    CashCloseSummary,
    CashCloseTransactionOut,
    OrganizationContext,
    Permission,
)

router = APIRouter(prefix="/v1/cash-closes", tags=["cash-closes"])


@router.post("/ensure", response_model=CashCloseOut)
async def ensure_open_close(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> CashCloseOut:
    result = await repository.rpc("cresko_ensure_open_close", {"p_org_id": context.org_id})
    return CashCloseOut.model_validate(result)


@router.get("", response_model=list[CashCloseOut])
async def list_cash_closes(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    limit: int = 100,
) -> list[CashCloseOut]:
    params: dict[str, str] = {
        "select": "id,org_id,number,opened_at,closed_at,status,opened_by,closed_by",
        "org_id": f"eq.{context.org_id}",
        "order": "created_at.desc",
        "limit": str(min(max(limit, 1), 500)),
    }
    rows = await repository.get_json("cash_closes", params)
    return [CashCloseOut.model_validate(row) for row in rows]


@router.get("/current", response_model=CashCloseOut | None)
async def current_cash_close(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> CashCloseOut | None:
    params: dict[str, str] = {
        "select": "id,org_id,number,opened_at,closed_at,status,opened_by,closed_by",
        "org_id": f"eq.{context.org_id}",
        "status": "eq.open",
        "order": "created_at.desc",
        "limit": "1",
    }
    rows = await repository.get_json("cash_closes", params)
    if not rows:
        return None
    return CashCloseOut.model_validate(rows[0])


@router.get("/{cash_close_id}", response_model=CashCloseOut)
async def get_cash_close(
    cash_close_id: str,
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> CashCloseOut:
    params: dict[str, str] = {
        "select": "id,org_id,number,opened_at,closed_at,status,opened_by,closed_by",
        "org_id": f"eq.{context.org_id}",
        "id": f"eq.{cash_close_id}",
    }
    rows = await repository.get_json("cash_closes", params)
    if not rows:
        raise HTTPException(status_code=404, detail="Cash close not found")
    return CashCloseOut.model_validate(rows[0])


@router.get("/{cash_close_id}/transactions", response_model=list[CashCloseTransactionOut])
async def cash_close_transactions(
    cash_close_id: str,
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[CashCloseTransactionOut]:
    params: dict[str, str] = {
        "org_id": f"eq.{context.org_id}",
        "cash_close_id": f"eq.{cash_close_id}",
        "order": "created_at.desc",
    }
    rows = await repository.get_json("cash_close_transactions", params)
    return [CashCloseTransactionOut.model_validate(row) for row in rows]


@router.post("/{cash_close_id}/close", response_model=CashCloseSummary)
async def close_cash_register(
    cash_close_id: str,
    context: Annotated[
        OrganizationContext,
        Depends(require_permissions(Permission.FINANCE_RECEIVE)),
    ],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> CashCloseSummary:
    result = await repository.rpc(
        "cresko_close_cash_register",
        {"p_org_id": context.org_id, "p_cash_close_id": cash_close_id},
    )
    return CashCloseSummary.model_validate(result)