from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from .dependencies import get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import OrganizationContext, Permission

router = APIRouter(prefix="/v1/backup", tags=["backup"])


class BackupImport(BaseModel):
    data: dict


@router.get("/export")
async def export_org(
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.ORG_MANAGE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> dict:
    result = await repository.rpc("cresko_export_org", {"p_org_id": context.org_id})
    return result


@router.post("/import")
async def import_org(
    payload: BackupImport,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.ORG_MANAGE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> dict:
    message = await repository.rpc(
        "cresko_import_org",
        {"p_org_id": context.org_id, "p_data": payload.data},
    )
    return {"message": message}