from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from .dependencies import get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    InvitationIn,
    InvitationOut,
    MemberOut,
    OrganizationContext,
    Permission,
)

router = APIRouter(prefix="/v1", tags=["members"])


@router.get("/members", response_model=list[MemberOut])
async def list_members(
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.MEMBERS_MANAGE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[MemberOut]:
    rows = await repository.rpc("cresko_org_members", {"p_org_id": context.org_id})
    return [MemberOut.model_validate(row) for row in rows]


@router.post("/members/invitations", response_model=InvitationOut, status_code=201)
async def invite_member(
    payload: InvitationIn,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.MEMBERS_MANAGE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> InvitationOut:
    rows = await repository.post_json(
        "org_invitations",
        {
            "org_id": context.org_id,
            "email": payload.email,
            "role_id": payload.role_id,
            "created_by": context.user_id,
        },
        prefer="return=representation",
    )
    return InvitationOut.model_validate(rows[0])


@router.post("/members/invitations/accept", status_code=201)
async def accept_invitation(
    body: dict,
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> dict:
    token = body.get("token")
    if not token:
        raise HTTPException(status_code=400, detail="token is required")
    result = await repository.rpc("cresko_accept_invitation", {"p_token": token})
    return {"accepted": True, "org_id": result["org_id"], "role_id": result.get("role_id")}


@router.get("/invitations", response_model=list[InvitationOut])
async def my_pending_invitations(
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[InvitationOut]:
    rows = await repository.get_json(
        "org_invitations",
        {"select": "id,org_id,email,role_id,status,token,created_at", "status": "eq.pending"},
    )
    return [InvitationOut.model_validate(row) for row in rows]