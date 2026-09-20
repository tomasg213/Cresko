-- Edición de productos existentes (campos + precios USD por lista).

create or replace function public.cresko_update_product(
  p_org_id uuid,
  p_product_id uuid,
  p_name text default null,
  p_description text default null,
  p_base_unit text default null,
  p_variants jsonb default '[]'::jsonb
) returns public.products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.products;
  v_variant jsonb;
  v_price jsonb;
  v_variant_id uuid;
  v_list_id uuid;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'catalog.write') then
    raise exception 'insufficient permissions';
  end if;

  select * into v_product
  from public.products
  where org_id = p_org_id and id = p_product_id;
  if v_product.id is null then
    raise exception 'product not found';
  end if;

  update public.products
  set name = coalesce(p_name, name),
      description = case when p_description is null then description else p_description end,
      base_unit = coalesce(p_base_unit, base_unit)
  where id = v_product.id;

  for v_variant in select value from jsonb_array_elements(p_variants)
  loop
    v_variant_id := (v_variant ->> 'variant_id')::uuid;
    select id into v_variant_id
    from public.product_variants
    where org_id = p_org_id and id = v_variant_id and product_id = v_product.id;
    if v_variant_id is null then
      raise exception 'variant not found';
    end if;

    update public.product_variants
    set name = coalesce(nullif(v_variant ->> 'name', ''), name),
        sku = coalesce(nullif(v_variant ->> 'sku', ''), sku)
    where id = v_variant_id;

    delete from public.variant_prices
    where org_id = p_org_id and variant_id = v_variant_id;

    for v_price in
      select value from jsonb_array_elements(coalesce(v_variant -> 'prices', '[]'::jsonb))
    loop
      select id into v_list_id
      from public.price_lists
      where org_id = p_org_id and code = v_price ->> 'price_list_code';
      if v_list_id is null then
        raise exception 'price list not found: %', v_price ->> 'price_list_code';
      end if;

      insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount)
      values (p_org_id, v_variant_id, v_list_id, 'USD', (v_price ->> 'amount')::numeric);
    end loop;
  end loop;

  return v_product;
end;
$$;

grant execute on function public.cresko_update_product(
  uuid, uuid, text, text, text, jsonb
) to authenticated;