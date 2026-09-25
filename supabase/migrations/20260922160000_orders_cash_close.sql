-- =====================================================================
-- Pedidos: también deben estar dentro de un cuadre de caja abierto.
-- =====================================================================

create or replace function public.cresko_create_order(
  p_org_id uuid,
  p_product_id uuid,
  p_party_id uuid,
  p_qty numeric,
  p_unit_price numeric,
  p_currency text,
  p_exchange_rate numeric,
  p_tax_rate numeric default 0,
  p_paid_amount numeric default 0,
  p_payment_method text default 'cash',
  p_expected_at date default null,
  p_notes text default null
) returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_close public.cash_closes;
  v_order public.orders;
  v_number bigint;
  v_subtotal numeric(18, 2);
  v_tax numeric(18, 2);
  v_total numeric(18, 2);
  v_paid numeric(18, 2);
  v_status text;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'sales.checkout') then
    raise exception 'insufficient permissions';
  end if;

  -- Cuadre de caja abierto del día.
  v_close := public.cresko_ensure_open_close(p_org_id);

  if p_qty is null or p_qty <= 0 then
    raise exception 'quantity must be positive';
  end if;
  if p_unit_price is null or p_unit_price < 0 then
    raise exception 'unit price must not be negative';
  end if;
  if p_currency not in ('VES', 'USD') then
    raise exception 'unsupported currency';
  end if;
  if p_exchange_rate is null or p_exchange_rate <= 0 then
    raise exception 'exchange rate must be positive';
  end if;
  if p_tax_rate is null or p_tax_rate < 0 then
    raise exception 'tax rate must not be negative';
  end if;
  if p_paid_amount is null or p_paid_amount < 0 then
    raise exception 'paid amount must not be negative';
  end if;
  if p_payment_method not in ('cash', 'card', 'transfer', 'credit', 'biopago') then
    raise exception 'unsupported payment method';
  end if;

  if not exists (
    select 1 from public.special_order_products
    where org_id = p_org_id and id = p_product_id and is_active
  ) then
    raise exception 'product under order not found';
  end if;
  if not exists (
    select 1 from public.parties
    where org_id = p_org_id and id = p_party_id and is_customer
  ) then
    raise exception 'customer not found';
  end if;

  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'order', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_number;

  v_subtotal := round(p_qty * p_unit_price, 2);
  v_tax := round(v_subtotal * p_tax_rate / 100, 2);
  v_total := round(v_subtotal + v_tax, 2);
  v_paid := least(round(p_paid_amount, 2), v_total);

  if v_paid >= v_total then
    v_status := 'paid';
  elsif v_paid > 0 then
    v_status := 'partial';
  else
    v_status := 'pending';
  end if;

  insert into public.orders (
    org_id, number, product_id, party_id, qty, unit_cost, unit_price,
    subtotal, tax, total, currency, exchange_rate, tax_rate,
    status, paid_amount, payment_method, expected_at, notes, created_by
  )
  values (
    p_org_id, format('PED-%s', lpad(v_number::text, 8, '0')), p_product_id, p_party_id,
    p_qty, p_unit_price, p_unit_price, v_subtotal, v_tax, v_total,
    p_currency, p_exchange_rate, p_tax_rate,
    v_status, v_paid, case when v_paid > 0 then p_payment_method else null end,
    p_expected_at, p_notes, auth.uid()
  )
  returning * into v_order;

  if v_paid > 0 then
    insert into public.order_payments (
      org_id, order_id, amount, currency, exchange_rate, method, created_by
    )
    values (
      p_org_id, v_order.id, v_paid, p_currency, p_exchange_rate,
      case when p_payment_method = 'credit' then 'cash' else p_payment_method end,
      auth.uid()
    );
  end if;

  return v_order;
end;
$$;

grant execute on function public.cresko_create_order(
  uuid, uuid, uuid, numeric, numeric, text, numeric, numeric, numeric, text, date, text
) to authenticated;