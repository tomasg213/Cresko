-- Datos de prueba (seed) para Cresko. Aplicar solo en entornos de desarrollo.

do $$
declare
  v_org uuid := '738b1286-b120-4728-a96c-5132a5b418fb';
  v_wh uuid := '4ef50506-96a0-4e14-b047-5247576c0fe3';
  v_user uuid := '5d863e0a-c02e-4d93-85e1-7742d3994c9a';
  v_retail uuid;
  v_wholesale uuid;
  v_pid uuid;
  v_vid uuid;
  v1 uuid; v2 uuid; v3 uuid; v4 uuid;
  v_inv_no bigint;
  v_inv_id uuid;
  v_cmp_no bigint;
  v_cmp_id uuid;
  v_party_maria uuid;
  v_party_sol uuid;
  v_party_pedro uuid;
  v_party_polar uuid;
  v_party_union uuid;
  v_party_guaire uuid;
begin
  select id into v_retail from public.price_lists where org_id = v_org and code = 'retail';
  select id into v_wholesale from public.price_lists where org_id = v_org and code = 'wholesale';

  -- ===================== CLIENTES =====================
  insert into public.parties (org_id, name, document_type, document_id, phone, email, is_customer, created_by) values
    (v_org, 'Maria Jose Contreras', 'ci', 'V-12345678', '0412-1234567', 'mjcontreras@correo.com', true, v_user),
    (v_org, 'Pedro Antonio Silva', 'ci', 'V-87654321', '0414-7654321', 'pedrosilva@correo.com', true, v_user),
    (v_org, 'Comercial El Sol C.A.', 'rif', 'J-30234567-8', '0212-5550100', 'ventas@elsol.com', true, v_user),
    (v_org, 'Carmen Elena Rojas', 'ci', 'V-24681357', '0424-9876543', 'carmenrojas@correo.com', true, v_user),
    (v_org, 'Inversiones Delta 2000 C.A.', 'rif', 'J-31567890-1', '0212-5550200', 'contacto@delta2000.com', true, v_user);

  select id into v_party_maria from public.parties where org_id = v_org and name = 'Maria Jose Contreras';
  select id into v_party_pedro from public.parties where org_id = v_org and name = 'Pedro Antonio Silva';
  select id into v_party_sol from public.parties where org_id = v_org and name = 'Comercial El Sol C.A.';

  -- ===================== PROVEEDORES =====================
  insert into public.parties (org_id, name, document_type, document_id, phone, email, is_supplier, created_by) values
    (v_org, 'Distribuidora Polar C.A.', 'rif', 'J-00023100-5', '0212-5550300', 'compras@polar.com', true, v_user),
    (v_org, 'Licoreria Union C.A.', 'rif', 'J-00042300-1', '0212-5550400', 'pedidos@unionlicor.com', true, v_user),
    (v_org, 'Distribuidora Alimentos La Guaira', 'rif', 'J-20567890-4', '0212-5550500', 'ventas@laguaira.com', true, v_user),
    (v_org, 'Fabrica de Refrescos del Centro', 'rif', 'J-24567890-0', '0212-5550600', 'ventas@refrescoscentro.com', true, v_user),
    (v_org, 'Importadora Nacional C.A.', 'rif', 'J-29876543-2', '0212-5550700', 'info@importadoranacional.com', true, v_user);

  select id into v_party_polar from public.parties where org_id = v_org and name = 'Distribuidora Polar C.A.';
  select id into v_party_union from public.parties where org_id = v_org and name = 'Licoreria Union C.A.';
  select id into v_party_guaire from public.parties where org_id = v_org and name = 'Distribuidora Alimentos La Guaira';

  -- ===================== ARTICULOS =====================
  -- Harina PAN 1kg
  insert into public.products (org_id, name, base_unit, is_taxable, created_by)
    values (v_org, 'Harina PAN 1kg', 'unit', true, v_user) returning id into v_pid;
  insert into public.product_variants (org_id, product_id, sku, name) values (v_org, v_pid, 'HPAN-1KG', 'Harina PAN 1kg') returning id into v_vid;
  v1 := v_vid;
  insert into public.barcodes (org_id, variant_id, barcode, is_primary) values (v_org, v_vid, '7790070000001', true);
  insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount) values
    (v_org, v_vid, v_retail, 'USD', 2.10), (v_org, v_vid, v_wholesale, 'USD', 1.85);
  insert into public.stock_levels (org_id, variant_id, warehouse_id, qty) values (v_org, v_vid, v_wh, 120);

  -- Azucar 1kg
  insert into public.products (org_id, name, base_unit, is_taxable, created_by)
    values (v_org, 'Azucar 1kg', 'unit', true, v_user) returning id into v_pid;
  insert into public.product_variants (org_id, product_id, sku, name) values (v_org, v_pid, 'AZU-1KG', 'Azucar 1kg') returning id into v_vid;
  insert into public.barcodes (org_id, variant_id, barcode, is_primary) values (v_org, v_vid, '7790070000002', true);
  insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount) values
    (v_org, v_vid, v_retail, 'USD', 1.20), (v_org, v_vid, v_wholesale, 'USD', 1.05);
  insert into public.stock_levels (org_id, variant_id, warehouse_id, qty) values (v_org, v_vid, v_wh, 200);

  -- Arroz 1kg
  insert into public.products (org_id, name, base_unit, is_taxable, created_by)
    values (v_org, 'Arroz 1kg', 'unit', true, v_user) returning id into v_pid;
  insert into public.product_variants (org_id, product_id, sku, name) values (v_org, v_pid, 'ARR-1KG', 'Arroz 1kg') returning id into v_vid;
  insert into public.barcodes (org_id, variant_id, barcode, is_primary) values (v_org, v_vid, '7790070000003', true);
  insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount) values
    (v_org, v_vid, v_retail, 'USD', 1.35), (v_org, v_vid, v_wholesale, 'USD', 1.18);
  insert into public.stock_levels (org_id, variant_id, warehouse_id, qty) values (v_org, v_vid, v_wh, 180);

  -- Ron Santa Teresa 1L
  insert into public.products (org_id, name, base_unit, is_taxable, created_by)
    values (v_org, 'Ron Santa Teresa 1L', 'unit', true, v_user) returning id into v_pid;
  insert into public.product_variants (org_id, product_id, sku, name) values (v_org, v_pid, 'RON-1L', 'Ron Santa Teresa 1L') returning id into v_vid;
  v2 := v_vid;
  insert into public.barcodes (org_id, variant_id, barcode, is_primary) values (v_org, v_vid, '7790070000004', true);
  insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount) values
    (v_org, v_vid, v_retail, 'USD', 12.00), (v_org, v_vid, v_wholesale, 'USD', 10.50);
  insert into public.stock_levels (org_id, variant_id, warehouse_id, qty) values (v_org, v_vid, v_wh, 60);

  -- Cerveza Polar Light 222ml
  insert into public.products (org_id, name, base_unit, is_taxable, created_by)
    values (v_org, 'Cerveza Polar Light 222ml', 'unit', true, v_user) returning id into v_pid;
  insert into public.product_variants (org_id, product_id, sku, name) values (v_org, v_pid, 'CPL-222', 'Cerveza Polar Light 222ml') returning id into v_vid;
  insert into public.barcodes (org_id, variant_id, barcode, is_primary) values (v_org, v_vid, '7790070000005', true);
  insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount) values
    (v_org, v_vid, v_retail, 'USD', 1.10), (v_org, v_vid, v_wholesale, 'USD', 0.95);
  insert into public.stock_levels (org_id, variant_id, warehouse_id, qty) values (v_org, v_vid, v_wh, 300);

  -- Agua Minalba 1L
  insert into public.products (org_id, name, base_unit, is_taxable, created_by)
    values (v_org, 'Agua Minalba 1L', 'unit', true, v_user) returning id into v_pid;
  insert into public.product_variants (org_id, product_id, sku, name) values (v_org, v_pid, 'AGU-1L', 'Agua Minalba 1L') returning id into v_vid;
  insert into public.barcodes (org_id, variant_id, barcode, is_primary) values (v_org, v_vid, '7790070000006', true);
  insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount) values
    (v_org, v_vid, v_retail, 'USD', 0.90), (v_org, v_vid, v_wholesale, 'USD', 0.75);
  insert into public.stock_levels (org_id, variant_id, warehouse_id, qty) values (v_org, v_vid, v_wh, 240);

  -- Sangria Caroreña 1,75L
  insert into public.products (org_id, name, base_unit, is_taxable, created_by)
    values (v_org, 'Sangria Caroreña 1,75L', 'unit', true, v_user) returning id into v_pid;
  insert into public.product_variants (org_id, product_id, sku, name) values (v_org, v_pid, 'SANG-175', 'Sangria Caroreña 1,75L') returning id into v_vid;
  insert into public.barcodes (org_id, variant_id, barcode, is_primary) values (v_org, v_vid, '7790070000007', true);
  insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount) values
    (v_org, v_vid, v_retail, 'USD', 4.50), (v_org, v_vid, v_wholesale, 'USD', 3.90);
  insert into public.stock_levels (org_id, variant_id, warehouse_id, qty) values (v_org, v_vid, v_wh, 80);

  -- Cafe Nescafe 200g
  insert into public.products (org_id, name, base_unit, is_taxable, created_by)
    values (v_org, 'Cafe Nescafe 200g', 'unit', true, v_user) returning id into v_pid;
  insert into public.product_variants (org_id, product_id, sku, name) values (v_org, v_pid, 'CAF-200', 'Cafe Nescafe 200g') returning id into v_vid;
  v3 := v_vid;
  insert into public.barcodes (org_id, variant_id, barcode, is_primary) values (v_org, v_vid, '7790070000008', true);
  insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount) values
    (v_org, v_vid, v_retail, 'USD', 6.50), (v_org, v_vid, v_wholesale, 'USD', 5.80);
  insert into public.stock_levels (org_id, variant_id, warehouse_id, qty) values (v_org, v_vid, v_wh, 90);

  -- Leche en polvo 900g
  insert into public.products (org_id, name, base_unit, is_taxable, created_by)
    values (v_org, 'Leche en polvo 900g', 'unit', true, v_user) returning id into v_pid;
  insert into public.product_variants (org_id, product_id, sku, name) values (v_org, v_pid, 'LEC-900', 'Leche en polvo 900g') returning id into v_vid;
  v4 := v_vid;
  insert into public.barcodes (org_id, variant_id, barcode, is_primary) values (v_org, v_vid, '7790070000009', true);
  insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount) values
    (v_org, v_vid, v_retail, 'USD', 8.00), (v_org, v_vid, v_wholesale, 'USD', 7.20);
  insert into public.stock_levels (org_id, variant_id, warehouse_id, qty) values (v_org, v_vid, v_wh, 70);

  -- ===================== CUENTAS POR COBRAR =====================
  -- Maria Jose Contreras: 1 Ron + 2 Cafe (credito)
  insert into public.invoice_sequences (org_id, last_number) values (v_org, 10)
    on conflict (org_id) do update set last_number = public.invoice_sequences.last_number + 1
    returning last_number into v_inv_no;
  insert into public.invoices (org_id, number, party_id, subtotal, tax, total, currency, exchange_rate, tax_rate, status, created_by)
    values (v_org, format('FAC-%s', lpad(v_inv_no::text, 8, '0')), v_party_maria, 12000.00, 1920.00, 13920.00, 'VES', 848.55, 16, 'posted', v_user)
    returning id into v_inv_id;
  insert into public.invoice_lines (org_id, invoice_id, variant_id, qty, unit_price, line_total, tax, currency) values
    (v_org, v_inv_id, v2, 1, 10182.60, 10182.60, 1629.22, 'VES'),
    (v_org, v_inv_id, v3, 1, 5515.58, 5515.58, 882.49, 'VES');
  insert into public.ar_ledger (org_id, party_id, invoice_id, entry_type, amount, currency, created_by)
    values (v_org, v_party_maria, v_inv_id, 'charge', 13920.00, 'VES', v_user);

  -- Comercial El Sol: 20 Arroz + 30 Cerveza (credito)
  insert into public.invoice_sequences (org_id, last_number) values (v_org, 11)
    on conflict (org_id) do update set last_number = public.invoice_sequences.last_number + 1
    returning last_number into v_inv_no;
  insert into public.invoices (org_id, number, party_id, subtotal, tax, total, currency, exchange_rate, tax_rate, status, created_by)
    values (v_org, format('FAC-%s', lpad(v_inv_no::text, 8, '0')), v_party_sol, 38000.00, 6080.00, 44080.00, 'VES', 848.55, 16, 'posted', v_user)
    returning id into v_inv_id;
  insert into public.invoice_lines (org_id, invoice_id, variant_id, qty, unit_price, line_total, tax, currency) values
    (v_org, v_inv_id, (select id from public.product_variants where org_id = v_org and sku = 'ARR-1KG'), 20, 1145.54, 22910.85, 3665.74, 'VES'),
    (v_org, v_inv_id, (select id from public.product_variants where org_id = v_org and sku = 'CPL-222'), 30, 933.41, 28002.15, 4480.34, 'VES');
  insert into public.ar_ledger (org_id, party_id, invoice_id, entry_type, amount, currency, created_by)
    values (v_org, v_party_sol, v_inv_id, 'charge', 44080.00, 'VES', v_user);

  -- Pedro Silva: 3 Leche (credito)
  insert into public.invoice_sequences (org_id, last_number) values (v_org, 12)
    on conflict (org_id) do update set last_number = public.invoice_sequences.last_number + 1
    returning last_number into v_inv_no;
  insert into public.invoices (org_id, number, party_id, subtotal, tax, total, currency, exchange_rate, tax_rate, status, created_by)
    values (v_org, format('FAC-%s', lpad(v_inv_no::text, 8, '0')), v_party_pedro, 20365.20, 3258.43, 23623.63, 'VES', 848.55, 16, 'posted', v_user)
    returning id into v_inv_id;
  insert into public.invoice_lines (org_id, invoice_id, variant_id, qty, unit_price, line_total, tax, currency) values
    (v_org, v_inv_id, v4, 3, 6788.40, 20365.20, 3258.43, 'VES');
  insert into public.ar_ledger (org_id, party_id, invoice_id, entry_type, amount, currency, created_by)
    values (v_org, v_party_pedro, v_inv_id, 'charge', 23623.63, 'VES', v_user);

  -- ===================== CUENTAS POR PAGAR =====================
  -- Distribuidora Polar
  insert into public.document_sequences (org_id, kind, last_number) values (v_org, 'purchase', 1)
    on conflict (org_id, kind) do update set last_number = public.document_sequences.last_number + 1
    returning last_number into v_cmp_no;
  insert into public.supplier_invoices (org_id, supplier_id, number, subtotal, tax, total, currency, exchange_rate, tax_rate, status, created_by)
    values (v_org, v_party_polar, format('CMP-%s', lpad(v_cmp_no::text, 8, '0')), 18000.00, 0.00, 18000.00, 'VES', 848.55, 0, 'posted', v_user)
    returning id into v_cmp_id;
  insert into public.ap_ledger (org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by)
    values (v_org, v_party_polar, v_cmp_id, 'charge', 18000.00, 'VES', v_user);

  -- Licoreria Union
  insert into public.document_sequences (org_id, kind, last_number) values (v_org, 'purchase', 2)
    on conflict (org_id, kind) do update set last_number = public.document_sequences.last_number + 1
    returning last_number into v_cmp_no;
  insert into public.supplier_invoices (org_id, supplier_id, number, subtotal, tax, total, currency, exchange_rate, tax_rate, status, created_by)
    values (v_org, v_party_union, format('CMP-%s', lpad(v_cmp_no::text, 8, '0')), 25000.00, 0.00, 25000.00, 'VES', 848.55, 0, 'posted', v_user)
    returning id into v_cmp_id;
  insert into public.ap_ledger (org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by)
    values (v_org, v_party_union, v_cmp_id, 'charge', 25000.00, 'VES', v_user);

  -- Distribuidora Alimentos La Guaira
  insert into public.document_sequences (org_id, kind, last_number) values (v_org, 'purchase', 3)
    on conflict (org_id, kind) do update set last_number = public.document_sequences.last_number + 1
    returning last_number into v_cmp_no;
  insert into public.supplier_invoices (org_id, supplier_id, number, subtotal, tax, total, currency, exchange_rate, tax_rate, status, created_by)
    values (v_org, v_party_guaire, format('CMP-%s', lpad(v_cmp_no::text, 8, '0')), 9000.00, 0.00, 9000.00, 'VES', 848.55, 0, 'posted', v_user)
    returning id into v_cmp_id;
  insert into public.ap_ledger (org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by)
    values (v_org, v_party_guaire, v_cmp_id, 'charge', 9000.00, 'VES', v_user);

  raise notice 'Seed completado';
end $$;