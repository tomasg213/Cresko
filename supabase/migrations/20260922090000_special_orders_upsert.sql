-- =====================================================================
-- Productos bajo pedido: upsert por variante.
-- Si la variante ya está registrada (aunque esté inactiva), se reactiva
-- y se actualiza el precio, en lugar de fallar por el constraint único.
-- =====================================================================

create or replace function public.cresko_create_special_product(
  p_org_id uuid,
  p_variant_id uuid,
  p_unit_price numeric default null,
  p_currency text default 'USD'
) returns public.special_order_products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.special_order_products;
  v_retail numeric;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'catalog.write') then
    raise exception 'insufficient permissions';
  end if;

  if not exists (
    select 1 from public.product_variants
    where org_id = p_org_id and id = p_variant_id
  ) then
    raise exception 'variant must exist in catalog';
  end if;
  if p_currency not in ('VES', 'USD') then
    raise exception 'unsupported currency';
  end if;

  -- Precio por defecto: retail USD del catálogo.
  if p_unit_price is null then
    select vp.amount into v_retail
    from public.variant_prices vp
    join public.price_lists pl on pl.id = vp.price_list_id and pl.org_id = vp.org_id
    where vp.org_id = p_org_id and vp.variant_id = p_variant_id
      and pl.code = 'retail' and vp.currency = 'USD'
    order by vp.amount
    limit 1;
    p_unit_price := coalesce(v_retail, 0);
  end if;
  if p_unit_price < 0 then
    raise exception 'unit price must not be negative';
  end if;

  -- Si ya existe (activa o inactiva), reactivar y actualizar precio.
  select * into v_product
  from public.special_order_products
  where org_id = p_org_id and variant_id = p_variant_id;

  if v_product.id is not null then
    update public.special_order_products
    set unit_price = p_unit_price,
        currency = p_currency,
        is_active = true
    where id = v_product.id
    returning * into v_product;
    return v_product;
  end if;

  insert into public.special_order_products (
    org_id, variant_id, unit_price, currency, created_by
  )
  values (p_org_id, p_variant_id, p_unit_price, p_currency, auth.uid())
  returning * into v_product;

  return v_product;
end;
$$;