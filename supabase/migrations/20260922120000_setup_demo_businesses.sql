-- =====================================================================
-- Portal de preview: siembra una organización demo según el tipo de
-- negocio. Recibe la org ya creada (con rol admin y membresía) y llena
-- catálogo, inventario, terceros, tasas, reposición y transacciones.
-- No depende de auth.uid(): usa p_user_id como autor de los registros.
--
-- p_business: 'abasto' | 'licoreria' | 'ropa' | 'carniceria' | 'verduleria'
-- =====================================================================

drop function if exists public.cresko_setup_demo(uuid, uuid);

create or replace function public.cresko_setup_demo(
  p_org_id uuid,
  p_user_id uuid,
  p_business text default 'abasto'
) returns text
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
  v_cat text;
  v_brand text;
  v_party uuid;
  v_supplier uuid;
  v_qty numeric;
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
  v_rate numeric := 854.00;
  v_line_total numeric;
  v_paid_usd numeric;
  v_balance_usd numeric;
  v_items jsonb;
  v_cats jsonb;
  v_brands jsonb;
  v_suppliers jsonb;
  v_customers jsonb;
  v_sale1 jsonb;
  v_sale2 jsonb;
  v_purchase jsonb;
  v_repl jsonb;
begin
  -- ============ DATASET SEGÚN EL TIPO DE NEGOCIO ============
  if p_business = 'licoreria' then
    v_cats := '["Cervezas","Vinos","Whisky","Ron","Destilados"]'::jsonb;
    v_brands := '["Polar","Santa Teresa","Buchanan","Pampers"]'::jsonb;
    v_items := '[
      {"name":"Cerveza Polar Light 222ml","sku":"CPL-222","cat":"Cervezas","brand":"Polar","retail":1.20,"whole":1.00,"stock":480,"bc":"7790070000201"},
      {"name":"Cerveza Solera 330ml","sku":"SOL-330","cat":"Cervezas","brand":"Polar","retail":1.50,"whole":1.30,"stock":360,"bc":"7790070000202"},
      {"name":"Vino Bodega Tinto 750ml","sku":"VIN-750","cat":"Vinos","brand":"Santa Teresa","retail":9.00,"whole":7.80,"stock":90,"bc":"7790070000203"},
      {"name":"Ron Santa Teresa 1L","sku":"RON-1L","cat":"Ron","brand":"Santa Teresa","retail":12.00,"whole":10.50,"stock":75,"bc":"7790070000204"},
      {"name":"Ron Cacique Añejo 750ml","sku":"RON-750","cat":"Ron","brand":"Santa Teresa","retail":10.50,"whole":9.00,"stock":60,"bc":"7790070000205"},
      {"name":"Whisky Buchanan 12 Años","sku":"WHI-12","cat":"Whisky","brand":"Buchanan","retail":35.00,"whole":31.00,"stock":30,"bc":"7790070000206"},
      {"name":"Sangria Caroreña 1,75L","sku":"SANG-175","cat":"Destilados","brand":"Polar","retail":4.50,"whole":3.90,"stock":120,"bc":"7790070000207"}
    ]'::jsonb;
    v_suppliers := '[
      {"name":"Licoreria Union C.A.","doc_type":"rif","doc_id":"J-00042300-1","phone":"0212-5558899","email":"pedidos@union.com"},
      {"name":"Distribuidora Polar C.A.","doc_type":"rif","doc_id":"J-00023100-5","phone":"0212-5556677","email":"ventas@polar.com"},
      {"name":"Importadora de Licores C.A.","doc_type":"rif","doc_id":"J-31567890-1","phone":"0212-5553344","email":"ventas@importlicores.com"}
    ]'::jsonb;
    v_customers := '[
      {"name":"Carlos Mendoza","doc_type":"ci","doc_id":"V-10.234.567","phone":"0414-1002003","email":"carlos.mendoza@example.com"},
      {"name":"Restaurante El Buen Sabor","doc_type":"rif","doc_id":"J-20567890-4","phone":"0212-5559900","email":"compras@elbuensabor.com"},
      {"name":"Bar La Esquina","doc_type":"rif","doc_id":"J-24567890-0","phone":"0416-3332211","email":"bar.esquina@example.com"},
      {"name":"María Torres","doc_type":"ci","doc_id":"V-15.678.901","phone":"0412-8887766","email":"maria.torres@example.com"}
    ]'::jsonb;
    v_sale1 := '[{"sku":"CPL-222","qty":12,"retail":1.20},{"sku":"RON-1L","qty":2,"retail":12.00}]'::jsonb;
    v_sale2 := '[{"sku":"WHI-12","qty":1,"retail":35.00},{"sku":"SANG-175","qty":3,"retail":4.50}]'::jsonb;
    v_purchase := '[{"sku":"CPL-222","qty":240,"cost":0.85},{"sku":"RON-1L","qty":48,"cost":9.20}]'::jsonb;
    v_repl := '[{"sku":"CPL-222","min":200,"max":600,"pack":24,"lead":4},{"sku":"RON-1L","min":20,"max":60,"pack":6,"lead":6},{"sku":"SANG-175","min":60,"max":180,"pack":12,"lead":5}]'::jsonb;
  elsif p_business = 'ropa' then
    v_cats := '["Hombre","Mujer","Calzado","Infantil","Accesorios"]'::jsonb;
    v_brands := '["Nike","Adidas","Levi","Zara","Puma"]'::jsonb;
    v_items := '[
      {"name":"Camisa Polo Hombre","sku":"CPO-M","cat":"Hombre","brand":"Zara","retail":18.00,"whole":15.00,"stock":80,"bc":"7790070000301"},
      {"name":"Jean Hombre 34","sku":"JEAN-34","cat":"Hombre","brand":"Levi","retail":35.00,"whole":30.00,"stock":55,"bc":"7790070000302"},
      {"name":"Blusa Mujer M","sku":"BLU-M","cat":"Mujer","brand":"Zara","retail":22.00,"whole":19.00,"stock":70,"bc":"7790070000303"},
      {"name":"Vestido Mujer S","sku":"VES-S","cat":"Mujer","brand":"Zara","retail":30.00,"whole":26.00,"stock":40,"bc":"7790070000304"},
      {"name":"Zapatillas Deportivas 42","sku":"ZAP-42","cat":"Calzado","brand":"Nike","retail":65.00,"whole":56.00,"stock":35,"bc":"7790070000305"},
      {"name":"Tenis Casual 40","sku":"TEN-40","cat":"Calzado","brand":"Adidas","retail":45.00,"whole":39.00,"stock":50,"bc":"7790070000306"},
      {"name":"Pantalón Infantil 8A","sku":"PAN-INF","cat":"Infantil","brand":"Puma","retail":15.00,"whole":12.00,"stock":90,"bc":"7790070000307"}
    ]'::jsonb;
    v_suppliers := '[
      {"name":"Importadora Textil C.A.","doc_type":"rif","doc_id":"J-30234567-8","phone":"0212-5551122","email":"ventas@importtextil.com"},
      {"name":"Calzados Nacionales C.A.","doc_type":"rif","doc_id":"J-29876543-2","phone":"0212-5556677","email":"ventas@calzadosnac.com"},
      {"name":"Distribuidora Moda C.A.","doc_type":"rif","doc_id":"J-00042300-1","phone":"0212-5558899","email":"pedidos@moda.com"}
    ]'::jsonb;
    v_customers := '[
      {"name":"Tienda de Variedades La Moda","doc_type":"rif","doc_id":"J-20567890-4","phone":"0212-5559900","email":"compras@lamoda.com"},
      {"name":"Ana Lucía Pérez","doc_type":"ci","doc_id":"V-12.345.678","phone":"0414-2223344","email":"ana.perez@example.com"},
      {"name":"Boutique Elegance","doc_type":"rif","doc_id":"J-24567890-0","phone":"0416-5556677","email":"ventas@boutiqueelegance.com"},
      {"name":"José Ramírez","doc_type":"ci","doc_id":"V-18.901.234","phone":"0412-9900112","email":"jose.ramirez@example.com"}
    ]'::jsonb;
    v_sale1 := '[{"sku":"CPO-M","qty":3,"retail":18.00},{"sku":"ZAP-42","qty":1,"retail":65.00}]'::jsonb;
    v_sale2 := '[{"sku":"BLU-M","qty":2,"retail":22.00},{"sku":"VES-S","qty":1,"retail":30.00}]'::jsonb;
    v_purchase := '[{"sku":"JEAN-34","qty":40,"cost":26.00},{"sku":"TEN-40","qty":30,"cost":33.00}]'::jsonb;
    v_repl := '[{"sku":"CPO-M","min":40,"max":120,"pack":6,"lead":7},{"sku":"ZAP-42","min":20,"max":60,"pack":2,"lead":9},{"sku":"PAN-INF","min":50,"max":150,"pack":6,"lead":6}]'::jsonb;
  elsif p_business = 'carniceria' then
    v_cats := '["Carnes rojas","Aves","Cerdo","Embutidos"]'::jsonb;
    v_brands := '["La Granja","Carnes del Llano","Procesados Goya"]'::jsonb;
    v_items := '[
      {"name":"Carne de Res Molida 1kg","sku":"RES-MO","cat":"Carnes rojas","brand":"Carnes del Llano","retail":6.50,"whole":5.80,"stock":120,"bc":"7790070000401"},
      {"name":"Solomo 1kg","sku":"SOLO-1","cat":"Carnes rojas","brand":"Carnes del Llano","retail":9.00,"whole":8.20,"stock":60,"bc":"7790070000402"},
      {"name":"Pechuga de Pollo 1kg","sku":"PECH-1","cat":"Aves","brand":"La Granja","retail":4.80,"whole":4.30,"stock":140,"bc":"7790070000403"},
      {"name":"Pierna de Pollo 1kg","sku":"PIER-1","cat":"Aves","brand":"La Granja","retail":3.90,"whole":3.50,"stock":150,"bc":"7790070000404"},
      {"name":"Chuleta de Cerdo 1kg","sku":"CHUL-1","cat":"Cerdo","brand":"La Granja","retail":5.20,"whole":4.70,"stock":90,"bc":"7790070000405"},
      {"name":"Chorizo Ahumado 500g","sku":"CHOR-5","cat":"Embutidos","brand":"Procesados Goya","retail":4.00,"whole":3.60,"stock":100,"bc":"7790070000406"},
      {"name":"Jamón Planchado 500g","sku":"JAMO-5","cat":"Embutidos","brand":"Procesados Goya","retail":3.50,"whole":3.10,"stock":110,"bc":"7790070000407"}
    ]'::jsonb;
    v_suppliers := '[
      {"name":"Matadero Central C.A.","doc_type":"rif","doc_id":"J-00023100-5","phone":"0212-5556677","email":"ventas@mataderocentral.com"},
      {"name":"Granja El Ávila C.A.","doc_type":"rif","doc_id":"J-00042300-1","phone":"0212-5558899","email":"pedidos@granjaavila.com"},
      {"name":"Embutidos del Centro C.A.","doc_type":"rif","doc_id":"J-31567890-1","phone":"0212-5553344","email":"ventas@embutidoscentro.com"}
    ]'::jsonb;
    v_customers := '[
      {"name":"Carnicería Don Pepe","doc_type":"rif","doc_id":"J-20567890-4","phone":"0212-5559900","email":"compras@donpepe.com"},
      {"name":"Restaurante El Fogón","doc_type":"rif","doc_id":"J-24567890-0","phone":"0416-5556677","email":"compras@elfogon.com"},
      {"name":"María Fernanda Rojas","doc_type":"ci","doc_id":"V-14.567.890","phone":"0412-3334455","email":"mafe.rojas@example.com"},
      {"name":"Supermercado La Estrella","doc_type":"rif","doc_id":"J-29876543-2","phone":"0212-5556677","email":"compras@laestrella.com"}
    ]'::jsonb;
    v_sale1 := '[{"sku":"RES-MO","qty":4,"retail":6.50},{"sku":"PECH-1","qty":3,"retail":4.80}]'::jsonb;
    v_sale2 := '[{"sku":"SOLO-1","qty":2,"retail":9.00},{"sku":"CHOR-5","qty":5,"retail":4.00}]'::jsonb;
    v_purchase := '[{"sku":"RES-MO","qty":80,"cost":5.00},{"sku":"PIER-1","qty":100,"cost":2.90}]'::jsonb;
    v_repl := '[{"sku":"RES-MO","min":60,"max":180,"pack":10,"lead":2},{"sku":"PECH-1","min":80,"max":220,"pack":10,"lead":2},{"sku":"CHOR-5","min":50,"max":150,"pack":10,"lead":4}]'::jsonb;
  elsif p_business = 'verduleria' then
    v_cats := '["Verduras","Frutas","Hortalizas","Tubérculos"]'::jsonb;
    v_brands := '["Huerto Central","Productos del Campo"]'::jsonb;
    v_items := '[
      {"name":"Tomate 1kg","sku":"TOM-1","cat":"Hortalizas","brand":"Huerto Central","retail":1.80,"whole":1.50,"stock":200,"bc":"7790070000501"},
      {"name":"Cebolla 1kg","sku":"CEB-1","cat":"Verduras","brand":"Huerto Central","retail":1.40,"whole":1.20,"stock":180,"bc":"7790070000502"},
      {"name":"Papa 1kg","sku":"PAP-1","cat":"Tubérculos","brand":"Productos del Campo","retail":1.20,"whole":1.00,"stock":250,"bc":"7790070000503"},
      {"name":"Lechuga","sku":"LECH","cat":"Verduras","brand":"Huerto Central","retail":1.00,"whole":0.85,"stock":120,"bc":"7790070000504"},
      {"name":"Plátano 1kg","sku":"PLA-1","cat":"Frutas","brand":"Productos del Campo","retail":1.10,"whole":0.90,"stock":160,"bc":"7790070000505"},
      {"name":"Naranja 1kg","sku":"NAR-1","cat":"Frutas","brand":"Huerto Central","retail":1.30,"whole":1.10,"stock":140,"bc":"7790070000506"},
      {"name":"Zanahoria 1kg","sku":"ZAN-1","cat":"Hortalizas","brand":"Huerto Central","retail":1.00,"whole":0.85,"stock":170,"bc":"7790070000507"}
    ]'::jsonb;
    v_suppliers := '[
      {"name":"Cosecha Fresca C.A.","doc_type":"rif","doc_id":"J-00023100-5","phone":"0212-5556677","email":"ventas@cosechafresca.com"},
      {"name":"Productos Agrícolas del Valle","doc_type":"rif","doc_id":"J-00042300-1","phone":"0212-5558899","email":"pedidos@valleagricola.com"}
    ]'::jsonb;
    v_customers := '[
      {"name":"Frutería Doña Rosa","doc_type":"rif","doc_id":"J-20567890-4","phone":"0212-5559900","email":"compras@donarosa.com"},
      {"name":"Restaurante Sabor Natural","doc_type":"rif","doc_id":"J-24567890-0","phone":"0416-5556677","email":"compras@sabornatural.com"},
      {"name":"Luis Enrique Silva","doc_type":"ci","doc_id":"V-11.222.333","phone":"0414-1112223","email":"luis.silva@example.com"},
      {"name":"Hogar Feliz C.A.","doc_type":"rif","doc_id":"J-29876543-2","phone":"0212-5556677","email":"compras@hogarfeliz.com"}
    ]'::jsonb;
    v_sale1 := '[{"sku":"TOM-1","qty":6,"retail":1.80},{"sku":"PAP-1","qty":10,"retail":1.20}]'::jsonb;
    v_sale2 := '[{"sku":"PLA-1","qty":8,"retail":1.10},{"sku":"NAR-1","qty":6,"retail":1.30}]'::jsonb;
    v_purchase := '[{"sku":"TOM-1","qty":150,"cost":1.20},{"sku":"PAP-1","qty":200,"cost":0.80}]'::jsonb;
    v_repl := '[{"sku":"TOM-1","min":80,"max":240,"pack":10,"lead":2},{"sku":"PAP-1","min":120,"max":300,"pack":25,"lead":2},{"sku":"PLA-1","min":80,"max":200,"pack":10,"lead":3}]'::jsonb;
  else
    -- abasto (predeterminado)
    v_cats := '["Abarrotes","Bebidas","Lácteos","Cuidado personal","Limpieza"]'::jsonb;
    v_brands := '["Minalba","Nestlé","Polar","Lior","Ariel"]'::jsonb;
    v_items := '[
      {"name":"Agua Minalba 1L","sku":"AGU-1L","cat":"Bebidas","brand":"Minalba","retail":0.90,"whole":0.75,"stock":420,"bc":"7790070000101"},
      {"name":"Cerveza Polar Light 222ml","sku":"CPL-222","cat":"Bebidas","brand":"Polar","retail":1.10,"whole":0.95,"stock":360,"bc":"7790070000200"},
      {"name":"Sangria Caroreña 1,75L","sku":"SANG-175","cat":"Bebidas","brand":"Polar","retail":4.50,"whole":3.90,"stock":140,"bc":"7790070000309"},
      {"name":"Arroz 1kg","sku":"ARR-1KG","cat":"Abarrotes","brand":"Nestlé","retail":1.35,"whole":1.18,"stock":180,"bc":"7790070000408"},
      {"name":"Azucar 1kg","sku":"AZU-1KG","cat":"Abarrotes","brand":"Nestlé","retail":1.20,"whole":1.05,"stock":220,"bc":"7790070000507"},
      {"name":"Harina PAN 1kg","sku":"HPAN-1KG","cat":"Abarrotes","brand":"Nestlé","retail":2.10,"whole":1.85,"stock":160,"bc":"7790070000606"},
      {"name":"Cafe Nescafe 200g","sku":"CAF-200","cat":"Abarrotes","brand":"Nestlé","retail":6.50,"whole":5.80,"stock":110,"bc":"7790070000705"},
      {"name":"Leche en polvo 900g","sku":"LEC-900","cat":"Lácteos","brand":"Nestlé","retail":8.00,"whole":7.20,"stock":90,"bc":"7790070000804"},
      {"name":"Colonia para bebe Lior","sku":"COL-BEBE","cat":"Cuidado personal","brand":"Lior","retail":3.50,"whole":3.00,"stock":65,"bc":"7790070001009"},
      {"name":"Detergente Ariel 1kg","sku":"ARI-1","cat":"Limpieza","brand":"Ariel","retail":4.20,"whole":3.70,"stock":95,"bc":"7790070001100"}
    ]'::jsonb;
    v_suppliers := '[
      {"name":"Distribuidora Polar C.A.","doc_type":"rif","doc_id":"J-00023100-5","phone":"0212-5556677","email":"ventas@polar.com"},
      {"name":"Licoreria Union C.A.","doc_type":"rif","doc_id":"J-00042300-1","phone":"0212-5558899","email":"pedidos@union.com"},
      {"name":"Distribuidora Alimentos La Guaira","doc_type":"rif","doc_id":"J-20567890-4","phone":"0212-5559900","email":"ventas@laguaira.com"}
    ]'::jsonb;
    v_customers := '[
      {"name":"Maria Jose Contreras","doc_type":"ci","doc_id":"V-12.345.678","phone":"0412-1234567","email":"maria@example.com"},
      {"name":"José Gutiérrez","doc_type":"ci","doc_id":"V-25.622.369","phone":"0416-7654321","email":"jose@example.com"},
      {"name":"Comercial El Sol C.A.","doc_type":"rif","doc_id":"J-30234567-8","phone":"0212-5551122","email":"ventas@elsol.com"},
      {"name":"Inversiones Delta 2000 C.A.","doc_type":"rif","doc_id":"J-31567890-1","phone":"0212-5553344","email":"compras@delta2000.com"}
    ]'::jsonb;
    v_sale1 := '[{"sku":"ARR-1KG","qty":3,"retail":1.35},{"sku":"AZU-1KG","qty":5,"retail":1.20},{"sku":"LEC-900","qty":1,"retail":8.00}]'::jsonb;
    v_sale2 := '[{"sku":"COL-BEBE","qty":3,"retail":3.50},{"sku":"CAF-200","qty":2,"retail":6.50}]'::jsonb;
    v_purchase := '[{"sku":"AGU-1L","qty":120,"cost":0.55},{"sku":"CPL-222","qty":200,"cost":0.70}]'::jsonb;
    v_repl := '[{"sku":"AGU-1L","min":120,"max":400,"pack":24,"lead":3},{"sku":"CPL-222","min":200,"max":600,"pack":24,"lead":4},{"sku":"HPAN-1KG","min":60,"max":200,"pack":12,"lead":3}]'::jsonb;
  end if;

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
  for v_cat in select jsonb_array_elements_text(v_cats)
  loop
    insert into public.categories (org_id, name) values (p_org_id, v_cat)
    on conflict do nothing;
  end loop;

  -- ============ MARCAS ============
  for v_brand in select jsonb_array_elements_text(v_brands)
  loop
    insert into public.brands (org_id, name) values (p_org_id, v_brand)
    on conflict do nothing;
  end loop;

  -- ============ PRODUCTOS Y STOCK ============
  for v_item in select value from jsonb_array_elements(v_items)
  loop
    insert into public.products (org_id, category_id, brand_id, name, base_unit, created_by)
    select p_org_id,
      (select id from public.categories where org_id = p_org_id and name = v_item ->> 'cat'),
      (select id from public.brands where org_id = p_org_id and name = v_item ->> 'brand'),
      v_item ->> 'name', 'unit', p_user_id
    returning id into v_prod;

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

  -- ============ TERCEROS ============
  insert into public.parties (org_id, name, document_type, document_id, phone, email, is_customer, created_by)
  select p_org_id, x->>'name', x->>'doc_type', x->>'doc_id', x->>'phone', x->>'email', true, p_user_id
  from jsonb_array_elements(v_customers) x;

  insert into public.parties (org_id, name, document_type, document_id, phone, email, is_supplier, created_by)
  select p_org_id, x->>'name', x->>'doc_type', x->>'doc_id', x->>'phone', x->>'email', true, p_user_id
  from jsonb_array_elements(v_suppliers) x;

  -- ============ TASAS DE CAMBIO (historial) ============
  insert into public.exchange_rates (org_id, rate_date, rate, source, created_by)
  select p_org_id, current_date - s, v_rate - s * 0.5, 'bcv', p_user_id
  from generate_series(0, 14) as s;

  -- ============ REPOSICIÓN ============
  insert into public.replenishment_config
    (org_id, variant_id, warehouse_id, min_qty, max_qty, pack_multiple, preferred_supplier_id, lead_time_days, is_active)
  select p_org_id, v.id, v_wh, (t->>'min')::numeric, (t->>'max')::numeric, (t->>'pack')::numeric,
    (select id from public.parties where org_id = p_org_id and is_supplier order by id limit 1),
    (t->>'lead')::int, true
  from jsonb_array_elements(v_repl) t
  join public.product_variants v on v.org_id = p_org_id and v.sku = t->>'sku'
  on conflict do nothing;

  -- ============ SECUENCIAS ============
  insert into public.invoice_sequences (org_id, last_number) values (p_org_id, 0);
  insert into public.document_sequences (org_id, kind, last_number) values
    (p_org_id, 'po', 0), (p_org_id, 'gr', 0), (p_org_id, 'purchase', 0);

  -- ============ VENTAS DE EJEMPLO ============
  -- Venta 1 (contado)
  select id into v_party from public.parties where org_id = p_org_id and is_customer order by id limit 1;
  insert into public.invoice_sequences (org_id, last_number)
  values (p_org_id, 1)
  on conflict (org_id) do update set last_number = public.invoice_sequences.last_number + 1
  returning last_number into v_inv_number;

  v_subtotal := 0;
  for v_line in select value from jsonb_array_elements(v_sale1)
  loop
    v_subtotal := v_subtotal + round((v_line ->> 'retail')::numeric * (v_line ->> 'qty')::numeric, 2);
  end loop;
  v_tax := round(v_subtotal * 16 / 100, 2);
  v_total := round(v_subtotal + v_tax, 2);
  v_paid_usd := round(v_total / v_rate, 2);

  insert into public.invoices (
    org_id, number, party_id, subtotal, tax, total, currency, exchange_rate, tax_rate, status, created_by
  )
  values (
    p_org_id, format('FAC-%s', lpad(v_inv_number::text, 8, '0')), v_party,
    round(v_subtotal,2), v_tax, v_total, 'VES', v_rate, 16, 'posted', p_user_id
  )
  returning id into v_invoice_id;

  for v_line in select value from jsonb_array_elements(v_sale1)
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

  insert into public.payments (org_id, invoice_id, amount, currency, exchange_rate, method, created_by)
  values (p_org_id, v_invoice_id, v_paid_usd, 'USD', v_rate, 'cash', p_user_id);

  -- Venta 2 (crédito) → queda CxC
  insert into public.invoice_sequences (org_id, last_number)
  values (p_org_id, 1)
  on conflict (org_id) do update set last_number = public.invoice_sequences.last_number + 1
  returning last_number into v_inv_number;

  select id into v_party from public.parties
  where org_id = p_org_id and is_customer order by id desc limit 1;

  v_subtotal := 0;
  for v_line in select value from jsonb_array_elements(v_sale2)
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

  for v_line in select value from jsonb_array_elements(v_sale2)
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
  select p_org_id, v_po_id, v.id, (t->>'qty')::numeric, (t->>'qty')::numeric, (t->>'cost')::numeric,
    round((t->>'qty')::numeric * (t->>'cost')::numeric, 2), 'USD'
  from jsonb_array_elements(v_purchase) t
  join public.product_variants v on v.org_id = p_org_id and v.sku = t->>'sku';

  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'gr', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_gr_number;

  insert into public.goods_receipts (org_id, po_id, number, received_at, notes, created_by)
  values (p_org_id, v_po_id, format('ENT-%s', lpad(v_gr_number::text, 8, '0')), current_date, 'Recepción inicial', p_user_id)
  returning id into v_receipt_id;

  v_subtotal := 0;
  for v_line in select value from jsonb_array_elements(v_purchase)
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

grant execute on function public.cresko_setup_demo(uuid, uuid, text) to authenticated;