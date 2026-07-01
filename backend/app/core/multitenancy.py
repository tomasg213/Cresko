from typing import AsyncGenerator

from fastapi import HTTPException, Request, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal


async def get_db_tenant(request: Request) -> AsyncGenerator[AsyncSession, None]:
    tenant_id: str | None = request.headers.get("X-Tenant-ID")

    if not tenant_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="X-Tenant-ID header is required",
        )

    session = AsyncSessionLocal()
    try:
        await session.execute(
            text(f"SET search_path TO tenant_{tenant_id}, public;")
        )
        yield session
        await session.commit()
    except Exception:
        await session.rollback()
        raise
    finally:
        await session.close()
