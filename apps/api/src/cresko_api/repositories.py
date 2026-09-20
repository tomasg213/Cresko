from typing import Any

import httpx

from .config import Settings
from .schemas import Membership


class SupabaseRepository:
    def __init__(self, settings: Settings, access_token: str) -> None:
        self._settings = settings
        self._access_token = access_token

    async def list_memberships(self, user_id: str) -> list[Membership]:
        rows = await self._request(
            "GET",
            "/memberships",
            params={
                "select": "org_id,role_id,role:org_roles(name,permissions)",
                "user_id": f"eq.{user_id}",
            },
        )
        result: list[Membership] = []
        for row in rows:
            role = row.get("role") or {}
            result.append(
                Membership(
                    org_id=row["org_id"],
                    role_id=row.get("role_id"),
                    role_name=role.get("name"),
                    permissions=role.get("permissions") or [],
                )
            )
        return result

    async def get_json(self, resource: str, params: dict[str, str]) -> Any:
        return await self._request("GET", f"/{resource}", params=params)

    async def post_json(self, resource: str, payload: dict[str, Any], prefer: str | None = None) -> Any:
        headers = {}
        if prefer:
            headers["Prefer"] = prefer
        return await self._request("POST", f"/{resource}", json=payload, headers=headers or None)

    async def patch_json(
        self,
        resource: str,
        payload: dict[str, Any],
        params: dict[str, str],
        prefer: str | None = None,
    ) -> Any:
        headers = {}
        if prefer:
            headers["Prefer"] = prefer
        return await self._request("PATCH", f"/{resource}", json=payload, params=params, headers=headers or None)

    async def delete_json(self, resource: str, params: dict[str, str]) -> None:
        await self._request("DELETE", f"/{resource}", params=params)

    async def rpc(self, function: str, payload: dict[str, Any]) -> Any:
        return await self._request("POST", f"/rpc/{function}", json=payload)

    async def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        headers = {
            "apikey": self._settings.supabase_anon_key,
            "Authorization": f"Bearer {self._access_token}",
        }
        headers.update(kwargs.pop("headers", {}) or {})
        if "json" in kwargs:
            headers["Content-Type"] = "application/json"

        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.request(method, f"{self._settings.rest_url}{path}", headers=headers, **kwargs)

        response.raise_for_status()
        if not response.content:
            return None
        return response.json()
