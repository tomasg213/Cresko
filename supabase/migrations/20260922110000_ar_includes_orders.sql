-- =====================================================================
-- CxC: el pago general de un cliente también cubre pedidos entregados
-- con saldo pendiente. La cascada aplica primero a las facturas más
-- antiguas y luego a los pedidos entregados (cada pedido se paga vía
-- cresko_pay_order, que elimina el pedido al saldarlo).
-- =====================================================================

create or replace function public.cresko_apply_ar_payment(
  p_org_id uuid,
  p_party_id uuid,
  p_amount numeric,
  p_currency text,
  p_method text default 'cash'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(18, 2) := round(p_amount, 2);
  v_total numeric(18, 2);
  v_remaining numeric(18, 2);
  v_row record;
  v_applied numeric(18, 2);
  v_inv public.invoices;
  v_order_id uuid;
  v_result jsonb := '[]'::jsonb;
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

  -- Deuda total: facturas (ar_ledger) + pedidos entregados con saldo.
  select coalesce(sum(balance), 0) into v_total
  from (
    select sum(amount) as balance
    from public.ar_ledger
    where org_id = p_org_id and party_id = p_party_id and currency = p_currency
    group by invoice_id
    having sum(amount) > 0
    union all
    select (o.total - o.paid_amount) as balance
    from public.orders o
    where o.org_id = p_org_id and o.party_id = p_party_id
      and o.currency = p_currency
      and o.delivery_status = 'delivered'
      and o.status <> 'cancelled'
      and (o.total - o.paid_amount) > 0
  ) b;

  if v_amount > v_total then
    raise exception 'El monto no puede ser mayor que toda la deuda';
  end if;

  v_remaining := v_amount;

  -- 1) Facturas más antiguas.
  for v_row in
    select a.invoice_id, sum(a.amount) as balance, min(i.created_at) as created_at
    from public.ar_ledger a
    join public.invoices i on i.id = a.invoice_id and i.org_id = a.org_id
    where a.org_id = p_org_id and a.party_id = p_party_id and a.currency = p_currency
    group by a.invoice_id
    having sum(a.amount) > 0
    order by min(i.created_at) asc, a.invoice_id asc
  loop
    exit when v_remaining <= 0;
    v_applied := least(v_remaining, v_row.balance);
    if v_applied > 0 then
      select * into v_inv from public.invoices where id = v_row.invoice_id;
      insert into public.payments (
        org_id, invoice_id, amount, currency, exchange_rate, method, created_by
      )
      values (
        p_org_id, v_row.invoice_id, v_applied, 'USD', v_inv.exchange_rate, p_method, auth.uid()
      );
      insert into public.ar_ledger (
        org_id, party_id, invoice_id, entry_type, amount, currency, created_by
      )
      values (
        p_org_id, p_party_id, v_row.invoice_id, 'payment', -v_applied, 'USD', auth.uid()
      );
      v_result := v_result || jsonb_build_object('invoice_id', v_row.invoice_id, 'amount', v_applied);
      v_remaining := round(v_remaining - v_applied, 2);
    end if;
  end loop;

  -- 2) Pedidos entregados con saldo, del más antiguo.
  for v_row in
    select o.id as order_id, (o.total - o.paid_amount) as balance, o.created_at
    from public.orders o
    where o.org_id = p_org_id and o.party_id = p_party_id
      and o.currency = p_currency
      and o.delivery_status = 'delivered'
      and o.status <> 'cancelled'
      and (o.total - o.paid_amount) > 0
    order by o.created_at asc, o.id asc
  loop
    exit when v_remaining <= 0;
    v_applied := least(v_remaining, v_row.balance);
    if v_applied > 0 then
      perform public.cresko_pay_order(p_org_id, v_row.order_id, v_applied, p_method);
      v_result := v_result || jsonb_build_object('order_id', v_row.order_id, 'amount', v_applied);
      v_remaining := round(v_remaining - v_applied, 2);
    end if;
  end loop;

  return v_result;
end;
$$;

grant execute on function public.cresko_apply_ar_payment(uuid, uuid, numeric, text, text) to authenticated;