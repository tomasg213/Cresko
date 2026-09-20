from cresko_api.schemas import Membership, OrganizationContext, Permission


def context(permissions: list[str]) -> OrganizationContext:
    return OrganizationContext(
        org_id="org-a",
        user_id="user-a",
        role_id="role-org-a",
        role_name="Rol de prueba",
        permissions=[Permission(p) for p in permissions],
    )


def membership(org_id: str, permissions: list[str]) -> Membership:
    return Membership(
        org_id=org_id,
        role_id=f"role-{org_id}",
        role_name="Rol de prueba",
        permissions=permissions,
    )