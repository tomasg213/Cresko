-- Los precios del catálogo se registran en USD (facturados luego a VES por la tasa del día).

create or replace function public.cresko_create_product(
  p_org_id uuid,
  p_name text,
  p_variants jsonb,
  p_category_id uuid default null,
  p_brand_id uuid default null,
  p_base_unit text default 'unit',
  p_description text default null
) returns public.products
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_product public.products;
  v_variant jsonb;
  v_barcode jsonb;
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

  insert into public.price_lists (org_id, code, name)
  values
    (p_org_id, 'retail', 'Detal'),
    (p_org_id, 'wholesale', 'Mayor')
  on conflict (org_id, code) do nothing;

  insert into public.products (
    org_id, name, description, category_id, brand_id, base_unit, created_by
  )
  values (
    p_org_id, p_name, p_description, p_category_id, p_brand_id, p_base_unit, auth.uid()
  )
  returning * into v_product;

  for v_variant in select value from jsonb_array_elements(p_variants)
  loop
    insert into public.product_variants (org_id, product_id, sku, name, attributes)
    values (
      p_org_id,
      v_product.id,
      coalesce(nullif(v_variant ->> 'sku', ''), gen_random_uuid()::text),
      coalesce(nullif(v_variant ->> 'name', ''), p_name),
      coalesce(v_variant -> 'attributes', '{}'::jsonb)
    )
    returning id into v_variant_id;

    for v_barcode in
      select value from jsonb_array_elements(coalesce(v_variant -> 'barcodes', '[]'::jsonb))
    loop
      insert into public.barcodes (org_id, variant_id, barcode, format, is_primary)
      values (
        p_org_id,
        v_variant_id,
        v_barcode ->> 'barcode',
        coalesce(nullif(v_barcode ->> 'format', ''), 'EAN13'),
        coalesce((v_barcode ->> 'is_primary')::boolean, false)
      );
    end loop;

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
      values (
        p_org_id,
        v_variant_id,
        v_list_id,
        'USD',
        (v_price ->> 'amount')::numeric
      );
    end loop;
  end loop;

  return v_product;
end;
$$;