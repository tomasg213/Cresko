import httpx
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .admin import router as admin_router
from .backup import router as backup_router
from .cash_closes import router as cash_closes_router
from .catalog import router as catalog_router
from .finance import router as finance_router
from .fx import router as fx_router
from .inventory import router as inventory_router
from .members import router as members_router
from .orders import router as orders_router
from .orgs import router as orgs_router
from .parties import router as parties_router
from .pos import router as pos_router
from .preview import router as preview_router
from .purchasing import router as purchasing_router
from .replenishment import router as replenishment_router
from .roles import router as roles_router
from .routes import router as api_router

app = FastAPI(title="Cresko API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:3001",
        "http://127.0.0.1:3001",
    ],
    allow_origin_regex=r"https?://((localhost|127\.0\.0\.1)(:\d+)?|[\w-]+\.vercel\.app|[\w-]+\.app\.vercel\.app)",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)
app.include_router(catalog_router)
app.include_router(inventory_router)
app.include_router(pos_router)
app.include_router(parties_router)
app.include_router(purchasing_router)
app.include_router(finance_router)
app.include_router(replenishment_router)
app.include_router(roles_router)
app.include_router(members_router)
app.include_router(orgs_router)
app.include_router(orders_router)
app.include_router(fx_router)
app.include_router(backup_router)
app.include_router(admin_router)
app.include_router(cash_closes_router)
app.include_router(preview_router)


@app.exception_handler(httpx.HTTPStatusError)
async def supabase_error_handler(request: Request, exc: httpx.HTTPStatusError) -> JSONResponse:
    detail = "Error del servicio de datos"
    try:
        body = exc.response.json()
        if isinstance(body, dict):
            detail = body.get("message") or body.get("details") or detail
        else:
            detail = str(body)
    except ValueError:
        detail = exc.response.text or detail
    return JSONResponse(status_code=400, content={"detail": detail})


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok"}