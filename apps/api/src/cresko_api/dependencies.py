from typing import Annotated

from fastapi import Depends, Header, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .auth import AuthenticatedUser, decode_access_token
from .config import Settings, get_settings
from .repositories import SupabaseRepository
from .schemas import Membership, OrganizationContext, Permission

bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AuthenticatedUser:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return decode_access_token(credentials.credentials, settings)


def get_supabase_repository(
    request: Request,
    settings: Annotated[Settings, Depends(get_settings)],
) -> SupabaseRepository:
    credentials = request.headers.get("authorization", "")
    access_token = credentials.removeprefix("Bearer ").strip()
    return SupabaseRepository(settings, access_token)


async def get_user_memberships(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[Membership]:
    return await repository.list_memberships(user.id)


async def get_current_membership(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    memberships: Annotated[list[Membership], Depends(get_user_memberships)],
    org_id: Annotated[str | None, Header(alias="X-Org-ID")] = None,
) -> OrganizationContext:

    if not memberships:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No organization membership")
    if org_id is None and len(memberships) == 1:
        selected = memberships[0]
    else:
        selected = next((item for item in memberships if item.org_id == org_id), None)
    if selected is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Organization access denied")

    return OrganizationContext(
        org_id=selected.org_id,
        user_id=user.id,
        role_id=selected.role_id,
        role_name=selected.role_name,
        permissions=[Permission(perm) for perm in selected.permissions],
    )


def require_permissions(*permissions: Permission):
    async def dependency(
        context: Annotated[OrganizationContext, Depends(get_current_membership)],
    ) -> OrganizationContext:
        missing = [permission for permission in permissions if permission not in context.permissions]
        if missing:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
        return context

    return dependency
