from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import (
    OrganizationContext,
    Permission,
    PermissionOut,
    RoleBrief,
    RoleCreate,
    RoleUpdate,
)

router = APIRouter(prefix="/v1/roles", tags=["roles"])


@router.get("/permissions", response_model=list[PermissionOut])
async def list_permissions(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[PermissionOut]:
    rows = await repository.get_json("permissions", {"order": "code.asc"})
    return [PermissionOut.model_validate(row) for row in rows]


@router.get("", response_model=list[RoleBrief])
async def list_roles(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[RoleBrief]:
    rows = await repository.get_json(
        "org_roles",
        {"org_id": f"eq.{context.org_id}", "order": "name.asc"},
    )
    return [RoleBrief.model_validate(row) for row in rows]


@router.post("", response_model=RoleBrief, status_code=201)
async def create_role(
    payload: RoleCreate,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.ROLES_MANAGE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> RoleBrief:
    rows = await repository.post_json(
        "org_roles",
        {
            "org_id": context.org_id,
            "name": payload.name,
            "permissions": [p.value for p in payload.permissions],
            "is_system": False,
        },
        prefer="return=representation",
    )
    return RoleBrief.model_validate(rows[0])


@router.put("/{role_id}", response_model=RoleBrief)
async def update_role(
    role_id: str,
    payload: RoleUpdate,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.ROLES_MANAGE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> RoleBrief:
    body: dict = {}
    if payload.name is not None:
        body["name"] = payload.name
    if payload.permissions is not None:
        body["permissions"] = [p.value for p in payload.permissions]
    if not body:
        raise HTTPException(status_code=400, detail="Nothing to update")

    params: dict[str, str] = {
        "org_id": f"eq.{context.org_id}",
        "id": f"eq.{role_id}",
        "select": "*",
    }
    rows = await repository.patch_json("org_roles", body, params, prefer="return=representation")
    if not rows:
        raise HTTPException(status_code=404, detail="Role not found")
    return RoleBrief.model_validate(rows[0])


@router.delete("/{role_id}", status_code=204)
async def delete_role(
    role_id: str,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.ROLES_MANAGE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> None:
    roles = await repository.get_json(
        "org_roles",
        {"org_id": f"eq.{context.org_id}", "id": f"eq.{role_id}"},
    )
    if not roles:
        raise HTTPException(status_code=404, detail="Role not found")
    if roles[0].get("is_system"):
        raise HTTPException(status_code=400, detail="System roles cannot be deleted")
    await repository.delete_json("org_roles", {"org_id": f"eq.{context.org_id}", "id": f"eq.{role_id}"})