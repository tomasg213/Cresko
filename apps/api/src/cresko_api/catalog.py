from typing import Annotated

import httpx
from fastapi import APIRouter, Depends, HTTPException

from .dependencies import get_current_membership, get_supabase_repository, require_permissions
from .repositories import SupabaseRepository
from .schemas import OrganizationContext, Permission, ProductCreate, ProductOut, ProductUpdate

router = APIRouter(prefix="/v1/catalog", tags=["catalog"])

_PRODUCT_SELECT = (
    "*,product_variants(*,barcodes(*),variant_prices("
    "id,price_list_id,currency,amount,price_list:price_lists(code)"
    "))"
)


@router.get("/products", response_model=list[ProductOut])
async def list_products(
    context: Annotated[OrganizationContext, Depends(get_current_membership)],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> list[ProductOut]:
    params = {
        "select": _PRODUCT_SELECT,
        "org_id": f"eq.{context.org_id}",
        "order": "name.asc",
    }
    rows = await repository.get_json("products", params)
    return [ProductOut.model_validate(row) for row in rows]


@router.post("/products", response_model=ProductOut, status_code=201)
async def create_product(
    payload: ProductCreate,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.CATALOG_WRITE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> ProductOut:
    body = {
        "p_org_id": context.org_id,
        "p_name": payload.name,
        "p_variants": [variant.model_dump(mode="json") for variant in payload.variants],
        "p_category_id": payload.category_id,
        "p_brand_id": payload.brand_id,
        "p_base_unit": payload.base_unit,
        "p_description": payload.description,
        "p_is_taxable": payload.is_taxable,
    }
    result = await repository.rpc("cresko_create_product", body)
    return ProductOut.model_validate(result)


@router.patch("/products/{product_id}", response_model=ProductOut)
async def update_product(
    product_id: str,
    payload: ProductUpdate,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.CATALOG_WRITE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> ProductOut:
    result = await repository.rpc(
        "cresko_update_product",
        {
            "p_org_id": context.org_id,
            "p_product_id": product_id,
            "p_name": payload.name,
            "p_description": payload.description,
            "p_base_unit": payload.base_unit,
            "p_variants": [variant.model_dump(mode="json") for variant in payload.variants],
            "p_is_taxable": payload.is_taxable,
        },
    )
    return ProductOut.model_validate(result)


@router.delete("/products/{product_id}", status_code=204)
async def delete_product(
    product_id: str,
    context: Annotated[OrganizationContext, Depends(require_permissions(Permission.CATALOG_WRITE))],
    repository: Annotated[SupabaseRepository, Depends(get_supabase_repository)],
) -> None:
    try:
        await repository.rpc(
            "cresko_delete_product",
            {"p_org_id": context.org_id, "p_product_id": product_id},
        )
    except httpx.HTTPStatusError as exc:
        detail = "No se pudo eliminar el producto"
        try:
            body = exc.response.json()
            detail = body.get("message") or body.get("details") or detail
        except ValueError:
            pass
        raise HTTPException(status_code=400, detail=detail) from exc