-- Edición/eliminación de reposiciones, órdenes de compra, terceros y pagos.
-- Documentos posteados (facturas, recibos, pagos) se corrigen con reversiones, no con UPDATE/DELETE.

alter table public.payments
  add column if not exists status text not null default 'posted' check (status in ('posted', 'void'));

create or replace function public.cresko_delete_purchase_order(
  p_org_id uuid,
  p_po_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'purchasing.write') then
    raise exception 'insufficient permissions';
  end if;

  if not exists (
    select 1 from public.purchase_orders
    where org_id = p_org_id and id = p_po_id
  ) then
    raise exception 'purchase order not found';
  end if;

  if exists (
    select 1 from public.purchase_orders
    where org_id = p_org_id and id = p_po_id and status not in ('draft', 'ordered')
  ) then
    raise exception 'no se puede eliminar: la orden ya fue recibida o anulada';
  end if;
  if exists (
    select 1 from public.goods_receipts
    where org_id = p_org_id and po_id = p_po_id
  ) then
    raise exception 'no se puede eliminar: la orden tiene recepciones';
  end if;
  if exists (
    select 1 from public.po_lines
    where org_id = p_org_id and po_id = p_po_id and qty_received > 0
  ) then
    raise exception 'no se puede eliminar: la orden tiene cantidades recibidas';
  end if;

  delete from public.po_lines
  where org_id = p_org_id and po_id = p_po_id;
  delete from public.purchase_orders
  where org_id = p_org_id and id = p_po_id;
end;
$$;

create or replace function public.cresko_update_purchase_order(
  p_org_id uuid,
  p_po_id uuid,
  p_supplier_id uuid,
  p_warehouse_id uuid,
  p_currency text,
  p_exchange_rate numeric,
  p_tax_rate numeric,
  p_expected_at date default null,
  p_notes text default null,
  p_lines jsonb default '[]'::jsonb
) returns public.purchase_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_po public.purchase_orders;
  v_line jsonb;
  v_qty numeric;
  v_cost numeric(18, 2);
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'purchasing.write') then
    raise exception 'insufficient permissions';
  end if;

  select * into v_po from public.purchase_orders
  where org_id = p_org_id and id = p_po_id;
  if v_po.id is null then
    raise exception 'purchase order not found';
  end if;
  if v_po.status not in ('draft', 'ordered') then
    raise exception 'no se puede editar: la orden ya fue recibida o anulada';
  end if;
  if exists (
    select 1 from public.goods_receipts
    where org_id = p_org_id and po_id = p_po_id
  ) then
    raise exception 'no se puede editar: la orden tiene recepciones';
  end if;

  if p_currency not in ('VES', 'USD') then
    raise exception 'unsupported currency';
  end if;
  if p_exchange_rate <= 0 then
    raise exception 'exchange rate must be positive';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    raise exception 'purchase order must have at least one line';
  end if;

  update public.purchase_orders
  set supplier_id = p_supplier_id,
      warehouse_id = p_warehouse_id,
      currency = p_currency,
      exchange_rate = p_exchange_rate,
      tax_rate = p_tax_rate,
      expected_at = p_expected_at,
      notes = p_notes
  where id = v_po.id;

  delete from public.po_lines
  where org_id = p_org_id and po_id = v_po.id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_qty := (v_line ->> 'qty')::numeric;
    v_cost := (v_line ->> 'unit_cost')::numeric;
    if v_qty <= 0 then
      raise exception 'quantity must be positive';
    end if;
    if v_cost < 0 then
      raise exception 'unit cost must not be negative';
    end if;

    insert into public.po_lines (
      org_id, po_id, variant_id, qty_ordered, qty_received,
      unit_cost, line_total, currency
    )
    values (
      p_org_id, v_po.id, (v_line ->> 'variant_id')::uuid, v_qty, 0,
      v_cost, round(v_cost * v_qty, 2), p_currency
    );
  end loop;

  return v_po;
end;
$$;

create or replace function public.cresko_delete_party(
  p_org_id uuid,
  p_party_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'catalog.write') then
    raise exception 'insufficient permissions';
  end if;

  if not exists (
    select 1 from public.parties
    where org_id = p_org_id and id = p_party_id
  ) then
    raise exception 'party not found';
  end if;

  if exists (
    select 1 from public.invoices where org_id = p_org_id and party_id = p_party_id
  ) or exists (
    select 1 from public.ar_ledger where org_id = p_org_id and party_id = p_party_id
  ) or exists (
    select 1 from public.ap_ledger where org_id = p_org_id and party_id = p_party_id
  ) or exists (
    select 1 from public.purchase_orders where org_id = p_org_id and supplier_id = p_party_id
  ) or exists (
    select 1 from public.supplier_invoices where org_id = p_org_id and supplier_id = p_party_id
  ) or exists (
    select 1 from public.replenishment_config
    where org_id = p_org_id and preferred_supplier_id = p_party_id
  ) then
    raise exception 'no se puede eliminar: el tercero tiene documentos asociados';
  end if;

  delete from public.parties
  where org_id = p_org_id and id = p_party_id;
end;
$$;

create or replace function public.cresko_void_payment(
  p_org_id uuid,
  p_payment_id uuid
) returns public.payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments;
  v_invoice public.invoices;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'finance.receive') then
    raise exception 'insufficient permissions';
  end if;

  select * into v_payment from public.payments
  where org_id = p_org_id and id = p_payment_id;
  if v_payment.id is null then
    raise exception 'payment not found';
  end if;
  if v_payment.status = 'void' then
    raise exception 'el pago ya fue anulado';
  end if;

  select * into v_invoice from public.invoices
  where org_id = p_org_id and id = v_payment.invoice_id;
  if v_invoice.id is null then
    raise exception 'invoice not found';
  end if;

  update public.payments
  set status = 'void'
  where id = v_payment.id;

  insert into public.ar_ledger (
    org_id, party_id, invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_invoice.party_id, v_invoice.id, 'reversal',
    v_payment.amount, v_payment.currency, auth.uid()
  );

  return v_payment;
end;
$$;

create or replace function public.cresko_void_ap_payment(
  p_org_id uuid,
  p_ledger_id uuid
) returns public.ap_ledger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ledger public.ap_ledger;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'finance.pay') then
    raise exception 'insufficient permissions';
  end if;

  select * into v_ledger from public.ap_ledger
  where org_id = p_org_id and id = p_ledger_id;
  if v_ledger.id is null then
    raise exception 'payment not found';
  end if;
  if v_ledger.entry_type <> 'payment' then
    raise exception 'no es un pago';
  end if;
  if exists (
    select 1 from public.ap_ledger
    where org_id = p_org_id
      and supplier_invoice_id = v_ledger.supplier_invoice_id
      and entry_type = 'reversal'
      and abs(amount) = abs(v_ledger.amount)
      and amount = -v_ledger.amount
      and created_at > v_ledger.created_at
  ) then
    raise exception 'el pago ya fue anulado';
  end if;

  insert into public.ap_ledger (
    org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_ledger.party_id, v_ledger.supplier_invoice_id, 'reversal',
    -v_ledger.amount, v_ledger.currency, auth.uid()
  );

  return v_ledger;
end;
$$;

grant execute on function public.cresko_delete_purchase_order(uuid, uuid) to authenticated;
grant execute on function public.cresko_update_purchase_order(
  uuid, uuid, uuid, uuid, text, numeric, numeric, date, text, jsonb
) to authenticated;
grant execute on function public.cresko_delete_party(uuid, uuid) to authenticated;
grant execute on function public.cresko_void_payment(uuid, uuid) to authenticated;
grant execute on function public.cresko_void_ap_payment(uuid, uuid) to authenticated;