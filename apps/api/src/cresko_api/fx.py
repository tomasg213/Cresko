from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from .bcv import BcvUnavailableError, fetch_bcv_rate
from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import FxRateOut, FxRateUpdate, OrganizationContext, Permission

router = APIRouter(prefix="/v1/fx", tags=["fx"])


@router.get("/rate", response_model=FxRateOut)
async def current_rate(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> FxRateOut:
    rate = await repository.rpc("cresko_current_exchange_rate", {"p_org_id": context.org_id})
    if rate is None:
        raise HTTPException(status_code=404, detail="No hay tasa de cambio configurada")
    rows = await repository.get_json(
        "exchange_rates",
        {"org_id": f"eq.{context.org_id}", "order": "rate_date.desc", "limit": "1"},
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No hay tasa de cambio configurada")
    return FxRateOut(
        rate=rate,
        rate_date=rows[0]["rate_date"],
        source=rows[0]["source"],
    )


@router.post("/rate", response_model=FxRateOut, status_code=201)
async def set_rate(
    payload: FxRateUpdate,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.ORG_MANAGE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> FxRateOut:
    result = await repository.rpc(
        "cresko_upsert_exchange_rate",
        {
            "p_org_id": context.org_id,
            "p_rate_date": payload.rate_date or datetime.now(UTC).date().isoformat(),
            "p_rate": str(payload.rate),
            "p_source": "manual",
        },
    )
    return FxRateOut(rate=result["rate"], rate_date=result["rate_date"], source=result["source"])


@router.post("/fetch", response_model=FxRateOut, status_code=201)
async def fetch_rate(
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.ORG_MANAGE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> FxRateOut:
    try:
        rate = await fetch_bcv_rate()
    except BcvUnavailableError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    result = await repository.rpc(
        "cresko_upsert_exchange_rate",
        {
            "p_org_id": context.org_id,
            "p_rate_date": datetime.now(UTC).date().isoformat(),
            "p_rate": str(round(rate, 2)),
            "p_source": "bcv",
        },
    )
    return FxRateOut(rate=result["rate"], rate_date=result["rate_date"], source=result["source"])