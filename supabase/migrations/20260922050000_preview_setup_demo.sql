-- =====================================================================
-- Portal de preview: siembra una organización demo completa.
-- Recibe la org ya creada (con rol admin y membresía) y llena catálogo,
-- inventario, terceros, tasas, reposición y transacciones de ejemplo.
-- No depende de auth.uid(): usa p_user_id como autor de los registros.
-- =====================================================================

create or replace function public.cresko_setup_demo(p_org_id uuid, p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_retail uuid;
  v_wholesale uuid;
  v_branch uuid;
  v_wh uuid;
  v_prod uuid;
  v_var uuid;
  v_cat record;
  v_brand record;
  v_party uuid;
  v_supplier uuid;
  v_qty numeric;
  v_price numeric;
  v_stock numeric;
  v_item jsonb;
  v_line jsonb;
  v_inv_number bigint;
  v_po_number bigint;
  v_gr_number bigint;
  v_purchase_number bigint;
  v_invoice_id uuid;
  v_po_id uuid;
  v_receipt_id uuid;
  v_si_id uuid;
  v_po_line uuid;
  v_subtotal numeric := 0;
  v_tax numeric;
  v_total numeric;
  v_ap_usd numeric;
  v_rate numeric := 854.00;
  v_line_total numeric;
  v_paid_usd numeric;
  v_balance_usd numeric;
begin
  -- ============ SUCURSAL Y ALMACÉN ============
  insert into public.branches (org_id, name, code, address, is_active)
  values (p_org_id, 'Sucursal Principal', 'PRIN', 'Av. Principal, Caracas', true)
  returning id into v_branch;

  insert into public.warehouses (org_id, branch_id, name, code, is_active)
  values (p_org_id, v_branch, 'Almacén Central', 'ALM01', true)
  returning id into v_wh;

  -- ============ LISTAS DE PRECIOS ============
  insert into public.price_lists (org_id, code, name, is_active) values
    (p_org_id, 'retail', 'Detal', true),
    (p_org_id, 'wholesale', 'Mayor', true);
  select id into v_retail from public.price_lists where org_id = p_org_id and code = 'retail';
  select id into v_wholesale from public.price_lists where org_id = p_org_id and code = 'wholesale';

  -- ============ CATEGORÍAS ============
  for v_cat in select * from (values
    ('Bebidas'), ('Abarrotes'), ('Lácteos'), ('Licores'), ('Cuidado personal')
  ) as t(name)
  loop
    insert into public.categories (org_id, name) values (p_org_id, v_cat.name);
  end loop;

  -- ============ MARCAS ============
  for v_brand in select * from (values
    ('Minalba'), ('Nestlé'), ('Polar'), ('Lior'), ('Santa Teresa')
  ) as t(name)
  loop
    insert into public.brands (org_id, name) values (p_org_id, v_brand.name);
  end loop;

  -- ============ PRODUCTOS Y STOCK ============
  -- name, sku, categoria, marca, retail, wholesale, stock
  for v_item in select value from jsonb_array_elements('[
    {"name":"Agua Minalba 1L","sku":"AGU-1L","cat":"Bebidas","brand":"Minalba","retail":0.90,"whole":0.75,"stock":420,"bc":"7790070000101"},
    {"name":"Cerveza Polar Light 222ml","sku":"CPL-222","cat":"Bebidas","brand":"Polar","retail":1.10,"whole":0.95,"stock":360,"bc":"7790070000200"},
    {"name":"Sangria Caroreña 1,75L","sku":"SANG-175","cat":"Bebidas","brand":"Polar","retail":4.50,"whole":3.90,"stock":140,"bc":"7790070000309"},
    {"name":"Arroz 1kg","sku":"ARR-1KG","cat":"Abarrotes","brand":"Nestlé","retail":1.35,"whole":1.18,"stock":180,"bc":"7790070000408"},
    {"name":"Azucar 1kg","sku":"AZU-1KG","cat":"Abarrotes","brand":"Nestlé","retail":1.20,"whole":1.05,"stock":220,"bc":"7790070000507"},
    {"name":"Harina PAN 1kg","sku":"HPAN-1KG","cat":"Abarrotes","brand":"Nestlé","retail":2.10,"whole":1.85,"stock":160,"bc":"7790070000606"},
    {"name":"Cafe Nescafe 200g","sku":"CAF-200","cat":"Abarrotes","brand":"Nestlé","retail":6.50,"whole":5.80,"stock":110,"bc":"7790070000705"},
    {"name":"Leche en polvo 900g","sku":"LEC-900","cat":"Lácteos","brand":"Nestlé","retail":8.00,"whole":7.20,"stock":90,"bc":"7790070000804"},
    {"name":"Ron Santa Teresa 1L","sku":"RON-1L","cat":"Licores","brand":"Santa Teresa","retail":12.00,"whole":10.50,"stock":75,"bc":"7790070000903"},
    {"name":"Colonia para bebe Lior","sku":"COL-BEBE","cat":"Cuidado personal","brand":"Lior","retail":3.50,"whole":3.00,"stock":65,"bc":"7790070001009"}
  ]'::jsonb) as item
  loop
    select id into v_prod from public.products where org_id = p_org_id and name = v_item ->> 'name';
    if v_prod is null then
      insert into public.products (org_id, category_id, brand_id, name, base_unit, created_by)
      select p_org_id,
        (select id from public.categories where org_id = p_org_id and name = v_item ->> 'cat'),
        (select id from public.brands where org_id = p_org_id and name = v_item ->> 'brand'),
        v_item ->> 'name', 'unit', p_user_id
      returning id into v_prod;
    end if;

    insert into public.product_variants (org_id, product_id, sku, name, attributes)
    values (p_org_id, v_prod, v_item ->> 'sku', v_item ->> 'name', '{}'::jsonb)
    returning id into v_var;

    insert into public.barcodes (org_id, variant_id, barcode, format, is_primary)
    values (p_org_id, v_var, v_item ->> 'bc', 'EAN13', true);

    insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount) values
      (p_org_id, v_var, v_retail, 'USD', (v_item ->> 'retail')::numeric),
      (p_org_id, v_var, v_wholesale, 'USD', (v_item ->> 'whole')::numeric);

    v_stock := (v_item ->> 'stock')::numeric;
    insert into public.stock_levels (org_id, variant_id, warehouse_id, qty)
    values (p_org_id, v_var, v_wh, v_stock);

    insert into public.stock_movements (
      org_id, variant_id, warehouse_id, movement_type, qty, balance_after,
      reference_type, reference_id, reason, created_by
    )
    values (
      p_org_id, v_var, v_wh, 'adjust', v_stock, v_stock,
      null, null, 'Stock inicial (demo)', p_user_id
    );
  end loop;

  -- ============ TERCEROS (CLIENTES Y PROVEEDORES) ============
  insert into public.parties (org_id, name, document_type, document_id, phone, email, is_customer, created_by)
  select p_org_id, x->>'name', x->>'doc_type', x->>'doc_id', x->>'phone', x->>'email', true, p_user_id
  from jsonb_array_elements('[
    {"name":"Maria Jose Contreras","doc_type":"ci","doc_id":"V-12.345.678","phone":"0412-1234567","email":"maria@example.com"},
    {"name":"José Gutiérrez","doc_type":"ci","doc_id":"V-25.622.369","phone":"0416-7654321","email":"jose@example.com"},
    {"name":"Comercial El Sol C.A.","doc_type":"rif","doc_id":"J-30234567-8","phone":"0212-5551122","email":"ventas@elsol.com"},
    {"name":"Inversiones Delta 2000 C.A.","doc_type":"rif","doc_id":"J-31567890-1","phone":"0212-5553344","email":"compras@delta2000.com"},
    {"name":"Consumidor Final","doc_type":"ci","doc_id":"V-1.234.567","phone":null,"email":null}
  ]'::jsonb) x;

  insert into public.parties (org_id, name, document_type, document_id, phone, email, is_supplier, created_by)
  select p_org_id, x->>'name', x->>'doc_type', x->>'doc_id', x->>'phone', x->>'email', true, p_user_id
  from jsonb_array_elements('[
    {"name":"Distribuidora Polar C.A.","doc_type":"rif","doc_id":"J-00023100-5","phone":"0212-5556677","email":"ventas@polar.com"},
    {"name":"Licoreria Union C.A.","doc_type":"rif","doc_id":"J-00042300-1","phone":"0212-5558899","email":"pedidos@union.com"},
    {"name":"Distribuidora Alimentos La Guaira","doc_type":"rif","doc_id":"J-20567890-4","phone":"0212-5559900","email":"ventas@laguaira.com"}
  ]'::jsonb) x;

  -- ============ TASAS DE CAMBIO (historial) ============
  insert into public.exchange_rates (org_id, rate_date, rate, source, created_by)
  select p_org_id, current_date - s, v_rate - s * 0.5, 'bcv', p_user_id
  from generate_series(0, 14) as s;

  -- ============ REPOSICIÓN ============
  insert into public.replenishment_config
    (org_id, variant_id, warehouse_id, min_qty, max_qty, pack_multiple, preferred_supplier_id, lead_time_days, is_active)
  select p_org_id, v.id, v_wh, t.min, t.max, t.pack,
    (select id from public.parties where org_id = p_org_id and is_supplier order by id limit 1),
    t.lead, true
  from (values
    ('AGU-1L', 120::numeric, 400::numeric, 24::numeric, 3),
    ('CPL-222', 200::numeric, 600::numeric, 24::numeric, 4),
    ('HPAN-1KG', 60::numeric, 200::numeric, 12::numeric, 3),
    ('LEC-900', 30::numeric, 120::numeric, 6::numeric, 5)
  ) as t(sku, min, max, pack, lead)
  join public.product_variants v on v.org_id = p_org_id and v.sku = t.sku;

  -- ============ SECUENCIAS ============
  insert into public.invoice_sequences (org_id, last_number) values (p_org_id, 0);
  insert into public.document_sequences (org_id, kind, last_number) values
    (p_org_id, 'po', 0), (p_org_id, 'gr', 0), (p_org_id, 'purchase', 0);

  -- ============ VENTAS DE EJEMPLO (contado y crédito) ============
  -- Venta 1 (contado): 3 Arroz + 5 Azúcar + 1 Leche
  select id into v_party from public.parties where org_id = p_org_id and is_customer order by id limit 1;
  insert into public.invoice_sequences (org_id, last_number)
  values (p_org_id, 1)
  on conflict (org_id) do update set last_number = public.invoice_sequences.last_number + 1
  returning last_number into v_inv_number;

  v_subtotal := 0;
  for v_line in select value from jsonb_array_elements('[
    {"sku":"ARR-1KG","qty":3,"retail":1.35},
    {"sku":"AZU-1KG","qty":5,"retail":1.20},
    {"sku":"LEC-900","qty":1,"retail":8.00}
  ]'::jsonb)
  loop
    v_subtotal := v_subtotal + round((v_line ->> 'retail')::numeric * (v_line ->> 'qty')::numeric, 2);
  end loop;
  v_tax := round(v_subtotal * 16 / 100, 2);
  v_total := round(v_subtotal + v_tax, 2);
  v_paid_usd := round(v_total / v_rate, 2);
  v_balance_usd := 0;

  insert into public.invoices (
    org_id, number, party_id, subtotal, tax, total, currency, exchange_rate, tax_rate, status, created_by
  )
  values (
    p_org_id, format('FAC-%s', lpad(v_inv_number::text, 8, '0')), v_party,
    round(v_subtotal,2), v_tax, v_total, 'VES', v_rate, 16, 'posted', p_user_id
  )
  returning id into v_invoice_id;

  for v_line in select value from jsonb_array_elements('[
    {"sku":"ARR-1KG","qty":3,"retail":1.35},
    {"sku":"AZU-1KG","qty":5,"retail":1.20},
    {"sku":"LEC-900","qty":1,"retail":8.00}
  ]'::jsonb)
  loop
    select id into v_var from public.product_variants where org_id = p_org_id and sku = v_line ->> 'sku';
    v_line_total := round((v_line ->> 'retail')::numeric * (v_line ->> 'qty')::numeric, 2);
    insert into public.invoice_lines (
      org_id, invoice_id, variant_id, qty, unit_price, line_total, tax, currency
    )
    values (
      p_org_id, v_invoice_id, v_var, (v_line ->> 'qty')::numeric,
      (v_line ->> 'retail')::numeric, v_line_total, round(v_line_total * 16 / 100, 2), 'VES'
    );
    -- stock sale
    select qty into v_qty from public.stock_levels
    where org_id = p_org_id and variant_id = v_var and warehouse_id = v_wh;
    update public.stock_levels set qty = qty - (v_line ->> 'qty')::numeric
    where org_id = p_org_id and variant_id = v_var and warehouse_id = v_wh;
    insert into public.stock_movements (
      org_id, variant_id, warehouse_id, movement_type, qty, balance_after,
      reference_type, reference_id, created_by
    )
    values (
      p_org_id, v_var, v_wh, 'sale', -((v_line ->> 'qty')::numeric), v_qty - (v_line ->> 'qty')::numeric,
      'invoice', v_invoice_id, p_user_id
    );
  end loop;

  insert into public.payments (org_id, invoice_id, amount, currency, exchange_rate, method, created_by)
  values (p_org_id, v_invoice_id, v_paid_usd, 'USD', v_rate, 'cash', p_user_id);

  -- Venta 2 (crédito): 2 Ron + 3 Colonia → queda CxC
  insert into public.invoice_sequences (org_id, last_number)
  values (p_org_id, 1)
  on conflict (org_id) do update set last_number = public.invoice_sequences.last_number + 1
  returning last_number into v_inv_number;

  select id into v_party from public.parties
  where org_id = p_org_id and is_customer and name = 'José Gutiérrez';

  v_subtotal := 0;
  for v_line in select value from jsonb_array_elements('[
    {"sku":"RON-1L","qty":2,"retail":12.00},
    {"sku":"COL-BEBE","qty":3,"retail":3.50}
  ]'::jsonb)
  loop
    v_subtotal := v_subtotal + round((v_line ->> 'retail')::numeric * (v_line ->> 'qty')::numeric, 2);
  end loop;
  v_tax := round(v_subtotal * 16 / 100, 2);
  v_total := round(v_subtotal + v_tax, 2);
  v_balance_usd := round(v_total / v_rate, 2);

  insert into public.invoices (
    org_id, number, party_id, subtotal, tax, total, currency, exchange_rate, tax_rate, status, created_by
  )
  values (
    p_org_id, format('FAC-%s', lpad(v_inv_number::text, 8, '0')), v_party,
    round(v_subtotal,2), v_tax, v_total, 'VES', v_rate, 16, 'posted', p_user_id
  )
  returning id into v_invoice_id;

  for v_line in select value from jsonb_array_elements('[
    {"sku":"RON-1L","qty":2,"retail":12.00},
    {"sku":"COL-BEBE","qty":3,"retail":3.50}
  ]'::jsonb)
  loop
    select id into v_var from public.product_variants where org_id = p_org_id and sku = v_line ->> 'sku';
    v_line_total := round((v_line ->> 'retail')::numeric * (v_line ->> 'qty')::numeric, 2);
    insert into public.invoice_lines (
      org_id, invoice_id, variant_id, qty, unit_price, line_total, tax, currency
    )
    values (
      p_org_id, v_invoice_id, v_var, (v_line ->> 'qty')::numeric,
      (v_line ->> 'retail')::numeric, v_line_total, round(v_line_total * 16 / 100, 2), 'VES'
    );
    select qty into v_qty from public.stock_levels
    where org_id = p_org_id and variant_id = v_var and warehouse_id = v_wh;
    update public.stock_levels set qty = qty - (v_line ->> 'qty')::numeric
    where org_id = p_org_id and variant_id = v_var and warehouse_id = v_wh;
    insert into public.stock_movements (
      org_id, variant_id, warehouse_id, movement_type, qty, balance_after,
      reference_type, reference_id, created_by
    )
    values (
      p_org_id, v_var, v_wh, 'sale', -((v_line ->> 'qty')::numeric), v_qty - (v_line ->> 'qty')::numeric,
      'invoice', v_invoice_id, p_user_id
    );
  end loop;

  insert into public.ar_ledger (
    org_id, party_id, invoice_id, entry_type, amount, currency, created_by
  )
  values (p_org_id, v_party, v_invoice_id, 'charge', v_balance_usd, 'USD', p_user_id);

  -- ============ COMPRA DE EJEMPLO (proveedor) ============
  select id into v_supplier from public.parties where org_id = p_org_id and is_supplier order by id limit 1;

  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'po', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_po_number;

  insert into public.purchase_orders (
    org_id, supplier_id, warehouse_id, number, status, currency, exchange_rate, tax_rate, created_by
  )
  values (
    p_org_id, v_supplier, v_wh, format('POC-%s', lpad(v_po_number::text, 8, '0')),
    'received', 'USD', 1.00, 0, p_user_id
  )
  returning id into v_po_id;

  insert into public.po_lines (org_id, po_id, variant_id, qty_ordered, qty_received, unit_cost, line_total, currency)
  select p_org_id, v_po_id, v.id, t.qty, t.qty, t.cost, round(t.qty * t.cost, 2), 'USD'
  from (values
    ('AGU-1L', 120::numeric, 0.55::numeric),
    ('CPL-222', 200::numeric, 0.70::numeric)
  ) as t(sku, qty, cost)
  join public.product_variants v on v.org_id = p_org_id and v.sku = t.sku;

  -- recepción de mercancía
  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'gr', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_gr_number;

  insert into public.goods_receipts (org_id, po_id, number, received_at, notes, created_by)
  values (p_org_id, v_po_id, format('ENT-%s', lpad(v_gr_number::text, 8, '0')), current_date, 'Recepción inicial', p_user_id)
  returning id into v_receipt_id;

  for v_line in select value from jsonb_array_elements('[
    {"sku":"AGU-1L","qty":120,"cost":0.55},
    {"sku":"CPL-222","qty":200,"cost":0.70}
  ]'::jsonb)
  loop
    select id into v_var from public.product_variants where org_id = p_org_id and sku = v_line ->> 'sku';
    select id into v_po_line from public.po_lines where org_id = p_org_id and po_id = v_po_id and variant_id = v_var;
    v_line_total := round((v_line ->> 'cost')::numeric * (v_line ->> 'qty')::numeric, 2);
    v_subtotal := v_subtotal + v_line_total;
    insert into public.receipt_lines (
      org_id, receipt_id, po_line_id, variant_id, qty, unit_cost, line_total, currency
    )
    values (
      p_org_id, v_receipt_id, v_po_line, v_var, (v_line ->> 'qty')::numeric,
      (v_line ->> 'cost')::numeric, v_line_total, 'USD'
    );
    select qty into v_qty from public.stock_levels
    where org_id = p_org_id and variant_id = v_var and warehouse_id = v_wh;
    update public.stock_levels set qty = qty + (v_line ->> 'qty')::numeric
    where org_id = p_org_id and variant_id = v_var and warehouse_id = v_wh;
    insert into public.stock_movements (
      org_id, variant_id, warehouse_id, movement_type, qty, balance_after,
      reference_type, reference_id, created_by
    )
    values (
      p_org_id, v_var, v_wh, 'purchase_receipt', (v_line ->> 'qty')::numeric,
      coalesce(v_qty, 0) + (v_line ->> 'qty')::numeric, 'goods_receipt', v_receipt_id, p_user_id
    );
  end loop;

  -- factura del proveedor y CxP
  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'purchase', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_purchase_number;

  insert into public.supplier_invoices (
    org_id, supplier_id, po_id, number, subtotal, tax, total, currency, exchange_rate, tax_rate, status, due_date, created_by
  )
  values (
    p_org_id, v_supplier, v_po_id, format('CMP-%s', lpad(v_purchase_number::text, 8, '0')),
    v_subtotal, 0, v_subtotal, 'USD', 1.00, 0, 'posted', current_date, p_user_id
  )
  returning id into v_si_id;

  insert into public.ap_ledger (
    org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by
  )
  values (p_org_id, v_supplier, v_si_id, 'charge', v_subtotal, 'USD', p_user_id);

  return 'Demo creada correctamente';
end;
$$;

grant execute on function public.cresko_setup_demo(uuid, uuid) to authenticated;