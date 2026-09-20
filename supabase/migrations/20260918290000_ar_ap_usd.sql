-- =====================================================================
-- CxC / CxP y pagos se registran en USD (los montos de venta siguen en VES).
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
  v_line_tax_usd numeric(18, 2);
  v_line_tax_ves numeric(18, 2);
  v_taxable boolean;
  v_subtotal_usd numeric(18, 2) := 0;
  v_tax_usd numeric(18, 2) := 0;
  v_total_usd numeric(18, 2);
  v_subtotal_ves numeric(18, 2) := 0;
  v_tax_ves numeric(18, 2) := 0;
  v_total_ves numeric(18, 2);
  v_paid_usd numeric(18, 2);
  v_balance_usd numeric(18, 2);
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
      v_line_tax_usd := round(v_line_usd * p_tax_rate / 100, 2);
    else
      v_line_tax_usd := 0;
    end if;
    v_line_tax_ves := round(v_line_tax_usd * p_exchange_rate, 2);

    v_subtotal_usd := v_subtotal_usd + v_line_usd;
    v_tax_usd := v_tax_usd + v_line_tax_usd;
    v_subtotal_ves := v_subtotal_ves + v_line_ves;
    v_tax_ves := v_tax_ves + v_line_tax_ves;
  end loop;

  v_total_usd := round(v_subtotal_usd + v_tax_usd, 2);
  v_total_ves := round(v_subtotal_ves + v_tax_ves, 2);
  v_paid_usd := least(round(coalesce(p_paid_amount, 0), 2), v_total_usd);
  v_balance_usd := greatest(round(v_total_usd - v_paid_usd, 2), 0);

  if v_balance_usd > 0 and v_party_id is null then
    raise exception 'credit sale requires a party';
  end if;
  if v_balance_usd > 0 and not public.has_permission(p_org_id, 'sales.credit') then
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
      v_line_tax_usd := round(v_line_usd * p_tax_rate / 100, 2);
    else
      v_line_tax_usd := 0;
    end if;
    v_line_tax_ves := round(v_line_tax_usd * p_exchange_rate, 2);

    insert into public.invoice_lines (
      org_id, invoice_id, variant_id, qty, unit_price, line_total, tax, currency
    )
    values (
      p_org_id, v_invoice_id, (v_line ->> 'variant_id')::uuid,
      v_qty, v_line_ves, v_line_ves, v_line_tax_ves, 'VES'
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

  if v_paid_usd > 0 then
    insert into public.payments (
      org_id, invoice_id, amount, currency, exchange_rate, method, created_by
    )
    values (
      p_org_id, v_invoice_id, v_paid_usd, 'USD', p_exchange_rate,
      p_payment_method, auth.uid()
    );
  end if;

  if v_balance_usd > 0 then
    insert into public.ar_ledger (
      org_id, party_id, invoice_id, entry_type, amount, currency, created_by
    )
    values (
      p_org_id, v_party_id, v_invoice_id, 'charge', v_balance_usd, 'USD', auth.uid()
    );
  end if;

  return v_invoice;
end;
$$;

-- =====================================================================
-- Cobro a cliente (en USD)
-- =====================================================================

create or replace function public.cresko_receive_payment(
  p_org_id uuid,
  p_party_id uuid,
  p_invoice_id uuid,
  p_amount numeric,
  p_currency text,
  p_method text default 'cash'
) returns public.payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.invoices;
  v_payment public.payments;
  v_amount numeric(18, 2) := round(p_amount, 2);
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'finance.receive') then
    raise exception 'insufficient permissions';
  end if;

  if v_amount <= 0 then
    raise exception 'payment must be positive';
  end if;
  if p_currency <> 'USD' then
    raise exception 'AR payments must be in USD';
  end if;
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select * into v_invoice from public.invoices
  where org_id = p_org_id and id = p_invoice_id;
  if v_invoice.id is null then
    raise exception 'invoice not found';
  end if;

  insert into public.payments (
    org_id, invoice_id, amount, currency, exchange_rate, method, created_by
  )
  values (
    p_org_id, v_invoice.id, v_amount, 'USD', v_invoice.exchange_rate, p_method, auth.uid()
  )
  returning * into v_payment;

  insert into public.ar_ledger (
    org_id, party_id, invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_invoice.party_id, v_invoice.id, 'payment', -v_amount, 'USD', auth.uid()
  );

  return v_payment;
end;
$$;

-- =====================================================================
-- Pago a proveedor (en USD)
-- =====================================================================

create or replace function public.cresko_pay_supplier(
  p_org_id uuid,
  p_supplier_invoice_id uuid,
  p_amount numeric,
  p_currency text,
  p_method text default 'cash'
) returns public.ap_ledger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.supplier_invoices;
  v_ledger public.ap_ledger;
  v_amount numeric(18, 2) := round(p_amount, 2);
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'finance.pay') then
    raise exception 'insufficient permissions';
  end if;

  if v_amount <= 0 then
    raise exception 'payment must be positive';
  end if;
  if p_currency <> 'USD' then
    raise exception 'AP payments must be in USD';
  end if;
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select * into v_invoice from public.supplier_invoices
  where org_id = p_org_id and id = p_supplier_invoice_id;
  if v_invoice.id is null then
    raise exception 'supplier invoice not found';
  end if;

  insert into public.ap_ledger (
    org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_invoice.supplier_id, v_invoice.id, 'payment', -v_amount, 'USD', auth.uid()
  )
  returning * into v_ledger;

  return v_ledger;
end;
$$;

-- =====================================================================
-- Recepción de mercancía: la CxP se registra en USD
-- =====================================================================

create or replace function public.cresko_receive_goods(
  p_org_id uuid,
  p_po_id uuid,
  p_lines jsonb,
  p_received_at date default current_date,
  p_notes text default null
) returns public.goods_receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_po public.purchase_orders;
  v_number bigint;
  v_receipt public.goods_receipts;
  v_line jsonb;
  v_po_line public.po_lines;
  v_qty numeric;
  v_receivable numeric;
  v_level public.stock_levels;
  v_subtotal numeric(18, 2) := 0;
  v_tax numeric(18, 2);
  v_total numeric(18, 2);
  v_ap_usd numeric(18, 2);
  v_inv_number bigint;
  v_supplier_invoice_id uuid;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'purchasing.receive') then
    raise exception 'insufficient permissions';
  end if;

  select * into v_po from public.purchase_orders
  where org_id = p_org_id and id = p_po_id;
  if v_po.id is null then
    raise exception 'purchase order not found';
  end if;
  if v_po.status in ('void', 'received') then
    raise exception 'purchase order cannot receive goods';
  end if;

  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'gr', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_number;

  insert into public.goods_receipts (org_id, po_id, number, received_at, notes, created_by)
  values (p_org_id, v_po.id, format('ENT-%s', lpad(v_number::text, 8, '0')), p_received_at, p_notes, auth.uid())
  returning * into v_receipt;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    select * into v_po_line
    from public.po_lines
    where org_id = p_org_id and id = (v_line ->> 'po_line_id')::uuid and po_id = v_po.id;
    if v_po_line.id is null then
      raise exception 'purchase order line not found';
    end if;

    v_qty := (v_line ->> 'qty')::numeric;
    if v_qty <= 0 then
      raise exception 'received quantity must be positive';
    end if;
    v_receivable := v_po_line.qty_ordered - v_po_line.qty_received;
    if v_qty > v_receivable then
      raise exception 'received quantity exceeds pending quantity';
    end if;

    insert into public.receipt_lines (
      org_id, receipt_id, po_line_id, variant_id, qty, unit_cost, line_total, currency
    )
    values (
      p_org_id, v_receipt.id, v_po_line.id, v_po_line.variant_id, v_qty,
      v_po_line.unit_cost, round(v_po_line.unit_cost * v_qty, 2), v_po_line.currency
    );

    update public.po_lines
    set qty_received = qty_received + v_qty
    where id = v_po_line.id;

    select * into v_level
    from public.stock_levels
    where org_id = p_org_id and variant_id = v_po_line.variant_id and warehouse_id = v_po.warehouse_id
    for update;

    if v_level.id is null then
      insert into public.stock_levels (org_id, variant_id, warehouse_id, qty)
      values (p_org_id, v_po_line.variant_id, v_po.warehouse_id, v_qty);
    else
      update public.stock_levels set qty = qty + v_qty where id = v_level.id;
    end if;

    insert into public.stock_movements (
      org_id, variant_id, warehouse_id, movement_type, qty, balance_after,
      reference_type, reference_id, created_by
    )
    values (
      p_org_id, v_po_line.variant_id, v_po.warehouse_id, 'purchase_receipt', v_qty,
      coalesce(v_level.qty, 0) + v_qty, 'goods_receipt', v_receipt.id, auth.uid()
    );

    v_subtotal := v_subtotal + round(v_po_line.unit_cost * v_qty, 2);
  end loop;

  update public.purchase_orders set
    status = case when exists (
      select 1 from public.po_lines
      where org_id = p_org_id and po_id = v_po.id and qty_received < qty_ordered
    ) then 'partial' else 'received' end
  where id = v_po.id;

  v_tax := round(v_subtotal * v_po.tax_rate / 100, 2);
  v_total := round(v_subtotal + v_tax, 2);
  v_ap_usd := case when v_po.currency = 'USD' then v_total else round(v_total / v_po.exchange_rate, 2) end;

  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'purchase', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_inv_number;

  insert into public.supplier_invoices (
    org_id, supplier_id, po_id, number, subtotal, tax, total,
    currency, exchange_rate, tax_rate, status, due_date, created_by
  )
  values (
    p_org_id, v_po.supplier_id, v_po.id, format('CMP-%s', lpad(v_inv_number::text, 8, '0')),
    v_subtotal, v_tax, v_total, v_po.currency, v_po.exchange_rate, v_po.tax_rate,
    'posted', p_received_at, auth.uid()
  )
  returning id into v_supplier_invoice_id;

  insert into public.ap_ledger (
    org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_po.supplier_id, v_supplier_invoice_id, 'charge', v_ap_usd, 'USD', auth.uid()
  );

  return v_receipt;
end;
$$;

-- =====================================================================
-- Convertir saldos existentes de VES a USD
-- =====================================================================

update public.ar_ledger a
set amount = round(a.amount / i.exchange_rate, 2), currency = 'USD'
from public.invoices i
where i.id = a.invoice_id and a.currency = 'VES' and a.entry_type <> 'reversal'
  and round(a.amount / i.exchange_rate, 2) <> 0;

update public.ap_ledger a
set amount = round(a.amount / si.exchange_rate, 2), currency = 'USD'
from public.supplier_invoices si
where si.id = a.supplier_invoice_id and a.currency = 'VES' and a.entry_type <> 'reversal'
  and round(a.amount / si.exchange_rate, 2) <> 0;

update public.payments p
set amount = round(p.amount / i.exchange_rate, 2), currency = 'USD'
from public.invoices i
where i.id = p.invoice_id and p.currency = 'VES'
  and round(p.amount / i.exchange_rate, 2) <> 0;
