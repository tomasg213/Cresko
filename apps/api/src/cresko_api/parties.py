from typing import Annotated

from fastapi import APIRouter, Depends

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import OrganizationContext, PartyCreate, PartyOut, Permission

router = APIRouter(prefix="/v1/parties", tags=["parties"])


@router.get("", response_model=list[PartyOut])
async def list_parties(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
    kind: str = "all",
) -> list[PartyOut]:
    params: dict[str, str] = {
        "select": "*",
        "org_id": f"eq.{context.org_id}",
        "order": "name.asc",
    }
    if kind == "customer":
        params["is_customer"] = "eq.true"
    elif kind == "supplier":
        params["is_supplier"] = "eq.true"
    rows = await repository.get_json("parties", params)
    return [PartyOut.model_validate(row) for row in rows]


@router.post("", response_model=PartyOut, status_code=201)
async def create_party(
    payload: PartyCreate,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.CATALOG_WRITE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> PartyOut:
    body = payload.model_dump(mode="json")
    body["org_id"] = context.org_id
    body["created_by"] = context.user_id
    rows = await repository.post_json("parties", body, prefer="return=representation")
    return PartyOut.model_validate(rows[0])