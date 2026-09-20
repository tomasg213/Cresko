-- Impuesto por producto (is_taxable) y checkout robusto (pago/cambio y errores).

alter table public.products add column is_taxable boolean not null default true;

-- =====================================================================
-- create_product con is_taxable
-- =====================================================================

drop function if exists public.cresko_create_product(uuid, text, jsonb, uuid, uuid, text, text);

create or replace function public.cresko_create_product(
  p_org_id uuid,
  p_name text,
  p_variants jsonb,
  p_category_id uuid default null,
  p_brand_id uuid default null,
  p_base_unit text default 'unit',
  p_description text default null,
  p_is_taxable boolean default true
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
    org_id, name, description, category_id, brand_id, base_unit, is_taxable, created_by
  )
  values (
    p_org_id, p_name, p_description, p_category_id, p_brand_id, p_base_unit,
    coalesce(p_is_taxable, true), auth.uid()
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

-- =====================================================================
-- update_product con is_taxable
-- =====================================================================

drop function if exists public.cresko_update_product(uuid, uuid, text, text, text, jsonb);

create or replace function public.cresko_update_product(
  p_org_id uuid,
  p_product_id uuid,
  p_name text default null,
  p_description text default null,
  p_base_unit text default null,
  p_variants jsonb default '[]'::jsonb,
  p_is_taxable boolean default null
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
      base_unit = coalesce(p_base_unit, base_unit),
      is_taxable = coalesce(p_is_taxable, is_taxable)
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

-- =====================================================================
-- checkout: impuesto por producto gravable y pago con cambio (no excede)
-- =====================================================================

create or replace function public.cresko_checkout(
  p_org_id uuid,
  p_warehouse_id uuid,
  p_price_list_code text,
  p_exchange_rate numeric,
  p_tax_rate numeric,
  p_lines jsonb,
  p_payment_method text default 'cash',
  p_paid_amount numeric default 0,
  p_party_id uuid default null,
  p_party jsonb default null
) returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_list_id uuid;
  v_number bigint;
  v_invoice public.invoices;
  v_line jsonb;
  v_price_usd numeric(18, 2);
  v_qty numeric(18, 3);
  v_line_usd numeric(18, 2);
  v_line_ves numeric(18, 2);
  v_line_tax numeric(18, 2);
  v_taxable boolean;
  v_subtotal_ves numeric(18, 2) := 0;
  v_tax_ves numeric(18, 2) := 0;
  v_total_ves numeric(18, 2);
  v_paid_eff numeric(18, 2);
  v_balance_ves numeric(18, 2);
  v_level public.stock_levels;
  v_party_id uuid;
  v_invoice_id uuid;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'sales.checkout') then
    raise exception 'insufficient permissions';
  end if;

  if p_exchange_rate is null or p_exchange_rate <= 0 then
    raise exception 'exchange rate must be positive';
  end if;
  if p_tax_rate < 0 then
    raise exception 'tax rate must not be negative';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    raise exception 'checkout must have at least one line';
  end if;

  select id into v_list_id
  from public.price_lists
  where org_id = p_org_id and code = p_price_list_code;
  if v_list_id is null then
    raise exception 'price list not found: %', p_price_list_code;
  end if;

  if p_party_id is null and p_party is not null then
    insert into public.parties (
      org_id, name, document_type, document_id, phone, email, is_customer, created_by
    )
    values (
      p_org_id,
      p_party ->> 'name',
      coalesce(nullif(p_party ->> 'document_type', ''), 'other'),
      nullif(p_party ->> 'document_id', ''),
      nullif(p_party ->> 'phone', ''),
      nullif(p_party ->> 'email', ''),
      true,
      auth.uid()
    )
    returning id into v_party_id;
  else
    v_party_id := p_party_id;
  end if;

  insert into public.invoice_sequences (org_id, last_number)
  values (p_org_id, 1)
  on conflict (org_id) do update set last_number = public.invoice_sequences.last_number + 1
  returning last_number into v_number;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_qty := (v_line ->> 'qty')::numeric;
    if v_qty <= 0 then
      raise exception 'quantity must be positive';
    end if;

    select amount into v_price_usd
    from public.variant_prices
    where org_id = p_org_id
      and variant_id = (v_line ->> 'variant_id')::uuid
      and price_list_id = v_list_id
      and currency = 'USD';
    if v_price_usd is null then
      raise exception 'no USD price for variant % in list %', v_line ->> 'variant_id', p_price_list_code;
    end if;

    select * into v_level
    from public.stock_levels
    where org_id = p_org_id
      and variant_id = (v_line ->> 'variant_id')::uuid
      and warehouse_id = p_warehouse_id
    for update;

    if v_level.id is null or v_level.qty < v_qty then
      raise exception 'insufficient stock for variant %', v_line ->> 'variant_id';
    end if;

    select coalesce(p.is_taxable, true) into v_taxable
    from public.product_variants v
    join public.products p on p.id = v.product_id and p.org_id = v.org_id
    where v.id = (v_line ->> 'variant_id')::uuid and v.org_id = p_org_id;

    v_line_usd := round(v_price_usd * v_qty, 2);
    v_line_ves := round(v_line_usd * p_exchange_rate, 2);
    if v_taxable then
      v_line_tax := round(v_line_ves * p_tax_rate / 100, 2);
    else
      v_line_tax := 0;
    end if;
    v_subtotal_ves := v_subtotal_ves + v_line_ves;
    v_tax_ves := v_tax_ves + v_line_tax;
  end loop;

  v_total_ves := round(v_subtotal_ves + v_tax_ves, 2);
  v_paid_eff := least(round(coalesce(p_paid_amount, 0), 2), v_total_ves);
  v_balance_ves := greatest(round(v_total_ves - v_paid_eff, 2), 0);

  if v_balance_ves > 0 and v_party_id is null then
    raise exception 'credit sale requires a party';
  end if;
  if v_balance_ves > 0 and not public.has_permission(p_org_id, 'sales.credit') then
    raise exception 'insufficient permissions for credit sale';
  end if;

  insert into public.invoices (
    org_id, number, party_id, subtotal, tax, total,
    currency, exchange_rate, tax_rate, status, created_by
  )
  values (
    p_org_id, format('FAC-%s', lpad(v_number::text, 8, '0')), v_party_id,
    v_subtotal_ves, v_tax_ves, v_total_ves, 'VES', p_exchange_rate, p_tax_rate, 'posted', auth.uid()
  )
  returning * into v_invoice;
  v_invoice_id := v_invoice.id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_qty := (v_line ->> 'qty')::numeric;
    select amount into v_price_usd
    from public.variant_prices
    where org_id = p_org_id
      and variant_id = (v_line ->> 'variant_id')::uuid
      and price_list_id = v_list_id
      and currency = 'USD';

    select coalesce(p.is_taxable, true) into v_taxable
    from public.product_variants v
    join public.products p on p.id = v.product_id and p.org_id = v.org_id
    where v.id = (v_line ->> 'variant_id')::uuid and v.org_id = p_org_id;

    v_line_usd := round(v_price_usd * v_qty, 2);
    v_line_ves := round(v_line_usd * p_exchange_rate, 2);
    if v_taxable then
      v_line_tax := round(v_line_ves * p_tax_rate / 100, 2);
    else
      v_line_tax := 0;
    end if;

    insert into public.invoice_lines (
      org_id, invoice_id, variant_id, qty, unit_price, line_total, tax, currency
    )
    values (
      p_org_id, v_invoice_id, (v_line ->> 'variant_id')::uuid,
      v_qty, v_line_ves, v_line_ves, v_line_tax, 'VES'
    );

    select * into v_level
    from public.stock_levels
    where org_id = p_org_id
      and variant_id = (v_line ->> 'variant_id')::uuid
      and warehouse_id = p_warehouse_id
    for update;

    update public.stock_levels
    set qty = v_level.qty - v_qty
    where id = v_level.id;

    insert into public.stock_movements (
      org_id, variant_id, warehouse_id, movement_type, qty, balance_after,
      reference_type, reference_id, created_by
    )
    values (
      p_org_id, (v_line ->> 'variant_id')::uuid, p_warehouse_id, 'sale',
      -v_qty, v_level.qty - v_qty, 'invoice', v_invoice_id, auth.uid()
    );
  end loop;

  if v_paid_eff > 0 then
    insert into public.payments (
      org_id, invoice_id, amount, currency, exchange_rate, method, created_by
    )
    values (
      p_org_id, v_invoice_id, v_paid_eff, 'VES', p_exchange_rate,
      p_payment_method, auth.uid()
    );
  end if;

  if v_balance_ves > 0 then
    insert into public.ar_ledger (
      org_id, party_id, invoice_id, entry_type, amount, currency, created_by
    )
    values (
      p_org_id, v_party_id, v_invoice_id, 'charge', v_balance_ves, 'VES', auth.uid()
    );
  end if;

  return v_invoice;
end;
$$;

grant execute on function public.cresko_create_product(
  uuid, text, jsonb, uuid, uuid, text, text, boolean
) to authenticated;
grant execute on function public.cresko_update_product(
  uuid, uuid, text, text, text, jsonb, boolean
) to authenticated;
grant execute on function public.cresko_checkout(
  uuid, uuid, text, numeric, numeric, jsonb, text, numeric, uuid, jsonb
) to authenticated;