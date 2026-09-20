create or replace function public.cresko_delete_product(
  p_org_id uuid,
  p_product_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_variant uuid;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'catalog.write') then
    raise exception 'insufficient permissions';
  end if;

  if not exists (
    select 1 from public.products
    where org_id = p_org_id and id = p_product_id
  ) then
    raise exception 'product not found';
  end if;

  for v_variant in
    select id from public.product_variants
    where org_id = p_org_id and product_id = p_product_id
  loop
    if exists (
      select 1 from public.stock_movements
      where org_id = p_org_id and variant_id = v_variant
    ) then
      raise exception 'no se puede eliminar: el producto tiene movimientos de inventario';
    end if;
    if exists (
      select 1 from public.invoice_lines
      where org_id = p_org_id and variant_id = v_variant
    ) then
      raise exception 'no se puede eliminar: el producto aparece en facturas';
    end if;
    if exists (
      select 1 from public.po_lines
      where org_id = p_org_id and variant_id = v_variant
    ) then
      raise exception 'no se puede eliminar: el producto aparece en órdenes de compra';
    end if;
  end loop;

  delete from public.replenishment_config
  where org_id = p_org_id
    and variant_id in (
      select id from public.product_variants
      where org_id = p_org_id and product_id = p_product_id
    );
  delete from public.stock_levels
  where org_id = p_org_id
    and variant_id in (
      select id from public.product_variants
      where org_id = p_org_id and product_id = p_product_id
    );
  delete from public.variant_prices
  where org_id = p_org_id
    and variant_id in (
      select id from public.product_variants
      where org_id = p_org_id and product_id = p_product_id
    );
  delete from public.barcodes
  where org_id = p_org_id
    and variant_id in (
      select id from public.product_variants
      where org_id = p_org_id and product_id = p_product_id
    );
  delete from public.product_variants
  where org_id = p_org_id and product_id = p_product_id;
  delete from public.products
  where org_id = p_org_id and id = p_product_id;
end;
$$;

grant execute on function public.cresko_delete_product(uuid, uuid) to authenticated;