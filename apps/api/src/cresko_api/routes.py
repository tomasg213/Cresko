from typing import Annotated

from fastapi import APIRouter, Depends

from .auth import AuthenticatedUser
from .dependencies import get_current_membership, get_current_user, get_user_memberships
from .schemas import CurrentUser, Membership, OrganizationContext

router = APIRouter(prefix="/v1", tags=["identity"])


@router.get("/me", response_model=CurrentUser)
async def current_user(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    memberships: Annotated[list[Membership], Depends(get_user_memberships)],
) -> CurrentUser:
    return CurrentUser(id=user.id, memberships=memberships)


@router.get("/context", response_model=OrganizationContext)
async def current_context(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
) -> OrganizationContext:
    return context
