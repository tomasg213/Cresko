from fastapi import Depends, FastAPI
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.multitenancy import get_db_tenant

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
)


@app.get("/api/v1/health")
async def health_check(db: AsyncSession = Depends(get_db_tenant)):
    return {
        "status": "healthy",
        "tenant_isolated": True,
    }
