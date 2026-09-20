-- =====================================================================
-- Respaldo y restauración del comercio (backup / restore)
-- =====================================================================

create or replace function public.cresko_export_org(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_data jsonb;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'org.manage') then
    raise exception 'insufficient permissions';
  end if;

  v_data := jsonb_build_object(
    'version', 1,
    'exported_at', now(),
    'organization', coalesce((select to_jsonb(o) from public.organizations o where o.id = p_org_id), 'null'::jsonb),
    'branches', coalesce((select jsonb_agg(to_jsonb(x)) from public.branches x where x.org_id = p_org_id), '[]'::jsonb),
    'warehouses', coalesce((select jsonb_agg(to_jsonb(x)) from public.warehouses x where x.org_id = p_org_id), '[]'::jsonb),
    'price_lists', coalesce((select jsonb_agg(to_jsonb(x)) from public.price_lists x where x.org_id = p_org_id), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(to_jsonb(x)) from public.categories x where x.org_id = p_org_id), '[]'::jsonb),
    'brands', coalesce((select jsonb_agg(to_jsonb(x)) from public.brands x where x.org_id = p_org_id), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(x)) from public.products x where x.org_id = p_org_id), '[]'::jsonb),
    'product_variants', coalesce((select jsonb_agg(to_jsonb(x)) from public.product_variants x where x.org_id = p_org_id), '[]'::jsonb),
    'barcodes', coalesce((select jsonb_agg(to_jsonb(x)) from public.barcodes x where x.org_id = p_org_id), '[]'::jsonb),
    'variant_prices', coalesce((select jsonb_agg(to_jsonb(x)) from public.variant_prices x where x.org_id = p_org_id), '[]'::jsonb),
    'parties', coalesce((select jsonb_agg(to_jsonb(x)) from public.parties x where x.org_id = p_org_id), '[]'::jsonb),
    'stock_levels', coalesce((select jsonb_agg(to_jsonb(x)) from public.stock_levels x where x.org_id = p_org_id), '[]'::jsonb),
    'stock_movements', coalesce((select jsonb_agg(to_jsonb(x)) from public.stock_movements x where x.org_id = p_org_id), '[]'::jsonb),
    'invoices', coalesce((select jsonb_agg(to_jsonb(x)) from public.invoices x where x.org_id = p_org_id), '[]'::jsonb),
    'invoice_lines', coalesce((select jsonb_agg(to_jsonb(x)) from public.invoice_lines x where x.org_id = p_org_id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(to_jsonb(x)) from public.payments x where x.org_id = p_org_id), '[]'::jsonb),
    'ar_ledger', coalesce((select jsonb_agg(to_jsonb(x)) from public.ar_ledger x where x.org_id = p_org_id), '[]'::jsonb),
    'purchase_orders', coalesce((select jsonb_agg(to_jsonb(x)) from public.purchase_orders x where x.org_id = p_org_id), '[]'::jsonb),
    'po_lines', coalesce((select jsonb_agg(to_jsonb(x)) from public.po_lines x where x.org_id = p_org_id), '[]'::jsonb),
    'goods_receipts', coalesce((select jsonb_agg(to_jsonb(x)) from public.goods_receipts x where x.org_id = p_org_id), '[]'::jsonb),
    'receipt_lines', coalesce((select jsonb_agg(to_jsonb(x)) from public.receipt_lines x where x.org_id = p_org_id), '[]'::jsonb),
    'supplier_invoices', coalesce((select jsonb_agg(to_jsonb(x)) from public.supplier_invoices x where x.org_id = p_org_id), '[]'::jsonb),
    'ap_ledger', coalesce((select jsonb_agg(to_jsonb(x)) from public.ap_ledger x where x.org_id = p_org_id), '[]'::jsonb),
    'replenishment_config', coalesce((select jsonb_agg(to_jsonb(x)) from public.replenishment_config x where x.org_id = p_org_id), '[]'::jsonb),
    'exchange_rates', coalesce((select jsonb_agg(to_jsonb(x)) from public.exchange_rates x where x.org_id = p_org_id), '[]'::jsonb),
    'invoice_sequences', coalesce((select to_jsonb(x) from public.invoice_sequences x where x.org_id = p_org_id), 'null'::jsonb),
    'document_sequences', coalesce((select jsonb_agg(to_jsonb(x)) from public.document_sequences x where x.org_id = p_org_id), '[]'::jsonb),
    'org_roles', coalesce((select jsonb_agg(to_jsonb(x)) from public.org_roles x where x.org_id = p_org_id), '[]'::jsonb),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object('email', u.email, 'role_name', r.name))
      from public.memberships m
      join public.auth_users_view u on u.id = m.user_id
      join public.org_roles r on r.id = m.role_id and r.org_id = m.org_id
      where m.org_id = p_org_id
    ), '[]'::jsonb)
  );
  return v_data;
end;
$$;

create or replace function public.cresko_import_org(p_org_id uuid, p_data jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version int;
  v_org jsonb;
  v_row jsonb;
  v_uid uuid;
  v_rid uuid;
  v_admin_role uuid;
  v_count int := 0;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'org.manage') then
    raise exception 'insufficient permissions';
  end if;

  v_version := (p_data ->> 'version')::int;
  if v_version is null or v_version <> 1 then
    raise exception 'respaldo no compatible (version esperada: 1)';
  end if;

  -- ============ BORRAR datos existentes del comercio (FK-safe) ============
  delete from public.payments where org_id = p_org_id;
  delete from public.ar_ledger where org_id = p_org_id;
  delete from public.invoice_lines where org_id = p_org_id;
  delete from public.invoices where org_id = p_org_id;
  delete from public.ap_ledger where org_id = p_org_id;
  delete from public.supplier_invoices where org_id = p_org_id;
  delete from public.receipt_lines where org_id = p_org_id;
  delete from public.goods_receipts where org_id = p_org_id;
  delete from public.po_lines where org_id = p_org_id;
  delete from public.purchase_orders where org_id = p_org_id;
  delete from public.stock_movements where org_id = p_org_id;
  delete from public.stock_levels where org_id = p_org_id;
  delete from public.replenishment_config where org_id = p_org_id;
  delete from public.variant_prices where org_id = p_org_id;
  delete from public.barcodes where org_id = p_org_id;
  delete from public.product_variants where org_id = p_org_id;
  delete from public.products where org_id = p_org_id;
  delete from public.categories where org_id = p_org_id;
  delete from public.brands where org_id = p_org_id;
  delete from public.price_lists where org_id = p_org_id;
  delete from public.exchange_rates where org_id = p_org_id;
  delete from public.document_sequences where org_id = p_org_id;
  delete from public.invoice_sequences where org_id = p_org_id;
  delete from public.memberships where org_id = p_org_id;
  delete from public.org_roles where org_id = p_org_id;
  delete from public.parties where org_id = p_org_id;
  delete from public.warehouses where org_id = p_org_id;
  delete from public.branches where org_id = p_org_id;

  -- ============ ORGANIZACIÓN ============
  v_org := p_data -> 'organization';
  if jsonb_typeof(v_org) = 'object' and v_org ? 'name' then
    update public.organizations set
      name = v_org ->> 'name',
      legal_name = nullif(v_org ->> 'legal_name', ''),
      tax_id = nullif(v_org ->> 'tax_id', ''),
      default_currency = coalesce(v_org ->> 'default_currency', default_currency),
      timezone = coalesce(v_org ->> 'timezone', timezone)
    where id = p_org_id;
  end if;

  -- ============ SUCURSALES / ALMACENES ============
  insert into public.branches (id, org_id, name, code, address, is_active, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, x->>'name', x->>'code', x->>'address',
         coalesce((x->>'is_active')::boolean, true), coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'branches') x;
  v_count := v_count + (select count(*) from jsonb_array_elements(p_data -> 'branches'));

  insert into public.warehouses (id, org_id, branch_id, name, code, is_active, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, (x->>'branch_id')::uuid, x->>'name', x->>'code',
         coalesce((x->>'is_active')::boolean, true), coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'warehouses') x;

  -- ============ LISTAS DE PRECIO / CATEGORÍAS / MARCAS ============
  insert into public.price_lists (id, org_id, code, name, is_active, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, x->>'code', x->>'name',
         coalesce((x->>'is_active')::boolean, true), coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'price_lists') x;

  insert into public.categories (id, org_id, name, parent_id, is_active, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, x->>'name', nullif(x->>'parent_id','')::uuid,
         coalesce((x->>'is_active')::boolean, true), coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'categories') x;

  insert into public.brands (id, org_id, name, is_active, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, x->>'name',
         coalesce((x->>'is_active')::boolean, true), coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'brands') x;

  -- ============ PRODUCTOS ============
  insert into public.products (id, org_id, category_id, brand_id, name, description, base_unit, is_taxable, is_active, created_by, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, nullif(x->>'category_id','')::uuid, nullif(x->>'brand_id','')::uuid,
         x->>'name', x->>'description', coalesce(x->>'base_unit','unit'),
         coalesce((x->>'is_taxable')::boolean, true), coalesce((x->>'is_active')::boolean, true),
         coalesce((select u.id from auth.users u where u.id = (x->>'created_by')::uuid), auth.uid()),
         coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'products') x;
  v_count := v_count + (select count(*) from jsonb_array_elements(p_data -> 'products'));

  insert into public.product_variants (id, org_id, product_id, sku, name, attributes, is_active, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, (x->>'product_id')::uuid, x->>'sku', x->>'name',
         coalesce(x->'attributes', '{}'::jsonb),
         coalesce((x->>'is_active')::boolean, true), coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'product_variants') x;

  insert into public.barcodes (id, org_id, variant_id, barcode, format, is_primary, created_at)
  select (x->>'id')::uuid, p_org_id, (x->>'variant_id')::uuid, x->>'barcode',
         coalesce(x->>'format','EAN13'), coalesce((x->>'is_primary')::boolean, false),
         coalesce((x->>'created_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'barcodes') x;

  insert into public.variant_prices (id, org_id, variant_id, price_list_id, currency, amount, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, (x->>'variant_id')::uuid, (x->>'price_list_id')::uuid,
         x->>'currency', (x->>'amount')::numeric,
         coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'variant_prices') x;

  -- ============ TERCEROS (clientes / proveedores) ============
  insert into public.parties (id, org_id, name, document_type, document_id, phone, email, is_customer, is_supplier, is_active, created_by, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, x->>'name', coalesce(x->>'document_type','other'), x->>'document_id',
         x->>'phone', x->>'email', coalesce((x->>'is_customer')::boolean, false), coalesce((x->>'is_supplier')::boolean, false),
         coalesce((x->>'is_active')::boolean, true),
         coalesce((select u.id from auth.users u where u.id = (x->>'created_by')::uuid), auth.uid()),
         coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'parties') x;
  v_count := v_count + (select count(*) from jsonb_array_elements(p_data -> 'parties'));

  -- ============ STOCK ============
  insert into public.stock_levels (id, org_id, variant_id, warehouse_id, qty, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, (x->>'variant_id')::uuid, (x->>'warehouse_id')::uuid,
         (x->>'qty')::numeric, coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'stock_levels') x;

  insert into public.stock_movements (id, org_id, variant_id, warehouse_id, movement_type, qty, balance_after, reference_type, reference_id, reason, created_by, created_at)
  select (x->>'id')::uuid, p_org_id, (x->>'variant_id')::uuid, (x->>'warehouse_id')::uuid,
         x->>'movement_type', (x->>'qty')::numeric, (x->>'balance_after')::numeric,
         nullif(x->>'reference_type',''), nullif(x->>'reference_id','')::uuid, x->>'reason',
         coalesce((select u.id from auth.users u where u.id = (x->>'created_by')::uuid), auth.uid()),
         coalesce((x->>'created_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'stock_movements') x;
  v_count := v_count + (select count(*) from jsonb_array_elements(p_data -> 'stock_movements'));

  -- ============ FACTURAS / PAGOS / CXC ============
  insert into public.invoices (id, org_id, number, party_id, subtotal, tax, total, currency, exchange_rate, tax_rate, status, created_by, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, x->>'number', nullif(x->>'party_id','')::uuid,
         (x->>'subtotal')::numeric, (x->>'tax')::numeric, (x->>'total')::numeric,
         x->>'currency', (x->>'exchange_rate')::numeric, (x->>'tax_rate')::numeric,
         coalesce(x->>'status','posted'),
         coalesce((select u.id from auth.users u where u.id = (x->>'created_by')::uuid), auth.uid()),
         coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'invoices') x;
  v_count := v_count + (select count(*) from jsonb_array_elements(p_data -> 'invoices'));

  insert into public.invoice_lines (id, org_id, invoice_id, variant_id, qty, unit_price, line_total, tax, currency, created_at)
  select (x->>'id')::uuid, p_org_id, (x->>'invoice_id')::uuid, (x->>'variant_id')::uuid,
         (x->>'qty')::numeric, (x->>'unit_price')::numeric, (x->>'line_total')::numeric,
         (x->>'tax')::numeric, x->>'currency', coalesce((x->>'created_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'invoice_lines') x;

  insert into public.payments (id, org_id, invoice_id, amount, currency, exchange_rate, method, created_by, created_at)
  select (x->>'id')::uuid, p_org_id, (x->>'invoice_id')::uuid, (x->>'amount')::numeric,
         x->>'currency', (x->>'exchange_rate')::numeric, coalesce(x->>'method','cash'),
         coalesce((select u.id from auth.users u where u.id = (x->>'created_by')::uuid), auth.uid()),
         coalesce((x->>'created_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'payments') x;

  insert into public.ar_ledger (id, org_id, party_id, invoice_id, entry_type, amount, currency, created_by, created_at)
  select (x->>'id')::uuid, p_org_id, (x->>'party_id')::uuid, (x->>'invoice_id')::uuid,
         x->>'entry_type', (x->>'amount')::numeric, x->>'currency',
         coalesce((select u.id from auth.users u where u.id = (x->>'created_by')::uuid), auth.uid()),
         coalesce((x->>'created_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'ar_ledger') x;

  -- ============ COMPRAS / CXP ============
  insert into public.purchase_orders (id, org_id, supplier_id, warehouse_id, number, status, currency, exchange_rate, tax_rate, expected_at, notes, created_by, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, (x->>'supplier_id')::uuid, (x->>'warehouse_id')::uuid,
         x->>'number', coalesce(x->>'status','ordered'), x->>'currency',
         (x->>'exchange_rate')::numeric, (x->>'tax_rate')::numeric,
         nullif(x->>'expected_at','')::date, x->>'notes',
         coalesce((select u.id from auth.users u where u.id = (x->>'created_by')::uuid), auth.uid()),
         coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'purchase_orders') x;

  insert into public.po_lines (id, org_id, po_id, variant_id, qty_ordered, qty_received, unit_cost, line_total, currency, created_at)
  select (x->>'id')::uuid, p_org_id, (x->>'po_id')::uuid, (x->>'variant_id')::uuid,
         (x->>'qty_ordered')::numeric, (x->>'qty_received')::numeric,
         (x->>'unit_cost')::numeric, (x->>'line_total')::numeric, x->>'currency',
         coalesce((x->>'created_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'po_lines') x;

  insert into public.goods_receipts (id, org_id, po_id, number, received_at, notes, created_by, created_at)
  select (x->>'id')::uuid, p_org_id, (x->>'po_id')::uuid, x->>'number',
         coalesce((x->>'received_at')::date, current_date), x->>'notes',
         coalesce((select u.id from auth.users u where u.id = (x->>'created_by')::uuid), auth.uid()),
         coalesce((x->>'created_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'goods_receipts') x;

  insert into public.receipt_lines (id, org_id, receipt_id, po_line_id, variant_id, qty, unit_cost, line_total, currency, created_at)
  select (x->>'id')::uuid, p_org_id, (x->>'receipt_id')::uuid, (x->>'po_line_id')::uuid, (x->>'variant_id')::uuid,
         (x->>'qty')::numeric, (x->>'unit_cost')::numeric, (x->>'line_total')::numeric, x->>'currency',
         coalesce((x->>'created_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'receipt_lines') x;

  insert into public.supplier_invoices (id, org_id, supplier_id, po_id, number, subtotal, tax, total, currency, exchange_rate, tax_rate, status, due_date, created_by, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, (x->>'supplier_id')::uuid, nullif(x->>'po_id','')::uuid,
         x->>'number', (x->>'subtotal')::numeric, (x->>'tax')::numeric, (x->>'total')::numeric,
         x->>'currency', (x->>'exchange_rate')::numeric, (x->>'tax_rate')::numeric,
         coalesce(x->>'status','posted'), nullif(x->>'due_date','')::date,
         coalesce((select u.id from auth.users u where u.id = (x->>'created_by')::uuid), auth.uid()),
         coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'supplier_invoices') x;

  insert into public.ap_ledger (id, org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by, created_at)
  select (x->>'id')::uuid, p_org_id, (x->>'party_id')::uuid, (x->>'supplier_invoice_id')::uuid,
         x->>'entry_type', (x->>'amount')::numeric, x->>'currency',
         coalesce((select u.id from auth.users u where u.id = (x->>'created_by')::uuid), auth.uid()),
         coalesce((x->>'created_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'ap_ledger') x;

  -- ============ REPOSICIÓN / TASAS ============
  insert into public.replenishment_config (id, org_id, variant_id, warehouse_id, min_qty, max_qty, pack_multiple, preferred_supplier_id, lead_time_days, is_active, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, (x->>'variant_id')::uuid, (x->>'warehouse_id')::uuid,
         (x->>'min_qty')::numeric, (x->>'max_qty')::numeric, (x->>'pack_multiple')::numeric,
         nullif(x->>'preferred_supplier_id','')::uuid, (x->>'lead_time_days')::int,
         coalesce((x->>'is_active')::boolean, true),
         coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'replenishment_config') x;

  insert into public.exchange_rates (id, org_id, rate_date, rate, source, created_by, created_at)
  select (x->>'id')::uuid, p_org_id, (x->>'rate_date')::date, (x->>'rate')::numeric,
         coalesce(x->>'source','manual'),
         (select u.id from auth.users u where u.id = (x->>'created_by')::uuid),
         coalesce((x->>'created_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'exchange_rates') x;

  -- ============ SECUENCIAS ============
  if jsonb_typeof(p_data -> 'invoice_sequences') = 'object' then
    insert into public.invoice_sequences (org_id, last_number)
    values (p_org_id, greatest(coalesce((p_data -> 'invoice_sequences' ->> 'last_number')::bigint, 0), coalesce((select last_number from public.invoice_sequences where org_id = p_org_id), 0)))
    on conflict (org_id) do update set last_number = greatest(public.invoice_sequences.last_number, excluded.last_number);
  end if;

  insert into public.document_sequences (org_id, kind, last_number)
  select p_org_id, x->>'kind', greatest((x->>'last_number')::bigint, 0)
  from jsonb_array_elements(p_data -> 'document_sequences') x
  on conflict (org_id, kind) do update set last_number = greatest(public.document_sequences.last_number, excluded.last_number);

  -- ============ ROLES / MIEMBROS ============
  insert into public.org_roles (id, org_id, name, permissions, is_system, created_at, updated_at)
  select (x->>'id')::uuid, p_org_id, x->>'name',
         coalesce((select array_agg(elem::text) from jsonb_array_elements_text(coalesce(x->'permissions', '[]'::jsonb)) elem), '{}'::text[]),
         coalesce((x->>'is_system')::boolean, false),
         coalesce((x->>'created_at')::timestamptz, now()), coalesce((x->>'updated_at')::timestamptz, now())
  from jsonb_array_elements(p_data -> 'org_roles') x;

  select id into v_admin_role from public.org_roles where org_id = p_org_id and is_system limit 1;
  if v_admin_role is null then
    insert into public.org_roles (org_id, name, permissions, is_system)
    values (p_org_id, 'Administrador', array(select code from public.permissions), true)
    returning id into v_admin_role;
  end if;
  insert into public.memberships (org_id, user_id, role_id)
  values (p_org_id, auth.uid(), v_admin_role)
  on conflict (org_id, user_id) do update set role_id = excluded.role_id;

  for v_row in select value from jsonb_array_elements(p_data -> 'memberships')
  loop
    select id into v_uid from auth.users u where lower(u.email) = lower(v_row ->> 'email');
    select id into v_rid from public.org_roles r where r.org_id = p_org_id and r.name = v_row ->> 'role_name';
    if v_uid is not null and v_rid is not null then
      insert into public.memberships (org_id, user_id, role_id)
      values (p_org_id, v_uid, v_rid)
      on conflict (org_id, user_id) do nothing;
    end if;
  end loop;

  return format('Respaldo restaurado correctamente (%s registros).', v_count);
end;
$$;

grant execute on function public.cresko_export_org(uuid) to authenticated;
grant execute on function public.cresko_import_org(uuid, jsonb) to authenticated;
