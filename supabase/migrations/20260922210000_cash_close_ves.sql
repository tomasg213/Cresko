-- =====================================================================
-- Cuadre de caja en Bolívares (VES).
-- La facturación es en Bs, por lo que los montos del cuadre (totales y
-- desglose por método de pago) se almacenan y muestran en VES.
-- =====================================================================

-- 1) Cambiar columnas de la tabla snapshot a VES.
drop view if exists public.cash_close_transactions_view;

alter table public.cash_close_transactions rename column total_usd to total_ves;
alter table public.cash_close_transactions rename column paid_usd to paid_ves;
alter table public.cash_close_transactions rename column balance_usd to balance_ves;
alter table public.cash_close_transactions rename column cash_usd to cash_ves;
alter table public.cash_close_transactions rename column card_usd to card_ves;
alter table public.cash_close_transactions rename column biopago_usd to biopago_ves;
alter table public.cash_close_transactions rename column credit_usd to credit_ves;

-- 2) Convertir snapshots existentes: el snapshot guardaba USD; la factura
-- y el pedido originales tienen la tasa para llevarlos a VES.
update public.cash_close_transactions t
set
  total_ves = round(t.total_ves * coalesce(er.rate, 1), 2),
  paid_ves = round(t.paid_ves * coalesce(er.rate, 1), 2),
  balance_ves = round(t.balance_ves * coalesce(er.rate, 1), 2),
  cash_ves = round(t.cash_ves * coalesce(er.rate, 1), 2),
  card_ves = round(t.card_ves * coalesce(er.rate, 1), 2),
  biopago_ves = round(t.biopago_ves * coalesce(er.rate, 1), 2),
  credit_ves = round(t.credit_ves * coalesce(er.rate, 1), 2)
from (
  select i.id as source_id, 'invoice' as source, i.exchange_rate as rate
  from public.invoices i
  union all
  select o.id, 'order', o.exchange_rate
  from public.orders o
) er
where er.source_id = t.source_id and er.source = t.source;

-- 3) Cerrar cuadre calculando en VES.
create or replace function public.cresko_close_cash_register(
  p_org_id uuid,
  p_cash_close_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_close public.cash_closes;
  v_total numeric(18, 2) := 0;
  v_paid numeric(18, 2) := 0;
  v_balance numeric(18, 2) := 0;
  v_cash numeric(18, 2) := 0;
  v_card numeric(18, 2) := 0;
  v_biopago numeric(18, 2) := 0;
  v_credit numeric(18, 2) := 0;
  v_tx_count int := 0;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'finance.receive') then
    raise exception 'insufficient permissions';
  end if;

  select * into v_close from public.cash_closes
  where org_id = p_org_id and id = p_cash_close_id;
  if v_close.id is null then
    raise exception 'cash close not found';
  end if;
  if v_close.status <> 'open' then
    raise exception 'cash close is already closed';
  end if;

  -- Facturas del cuadre (rango opened_at..now) en VES.
  insert into public.cash_close_transactions (
    org_id, cash_close_id, source, source_id, number, party_name,
    total_ves, paid_ves, balance_ves, cash_ves, card_ves, biopago_ves, credit_ves
  )
  select
    p_org_id, p_cash_close_id, 'invoice', i.id, i.number, p.name,
    i.total,
    round(coalesce(pay.paid, 0) * i.exchange_rate, 2),
    greatest(round(i.total - coalesce(pay.paid, 0) * i.exchange_rate, 2), 0),
    round(coalesce(pay.cash, 0) * i.exchange_rate, 2),
    round(coalesce(pay.card, 0) * i.exchange_rate, 2),
    round(coalesce(pay.biopago, 0) * i.exchange_rate, 2),
    greatest(round(i.total - coalesce(pay.paid, 0) * i.exchange_rate, 2), 0)
  from public.invoices i
  left join public.parties p on p.id = i.party_id and p.org_id = i.org_id
  left join (
    select invoice_id,
      sum(amount) filter (where method = 'cash') as cash,
      sum(amount) filter (where method = 'card') as card,
      sum(amount) filter (where method = 'biopago') as biopago,
      sum(amount) as paid
    from public.payments
    where org_id = p_org_id
    group by invoice_id
  ) pay on pay.invoice_id = i.id
  where i.org_id = p_org_id
    and i.created_at >= v_close.opened_at
    and i.created_at <= coalesce(v_close.closed_at, now())
    and not exists (
      select 1 from public.cash_close_transactions t
      where t.org_id = p_org_id and t.source = 'invoice' and t.source_id = i.id
    );

  -- Pedidos del cuadre en VES.
  insert into public.cash_close_transactions (
    org_id, cash_close_id, source, source_id, number, party_name,
    total_ves, paid_ves, balance_ves, cash_ves, card_ves, biopago_ves, credit_ves
  )
  select
    p_org_id, p_cash_close_id, 'order', o.id, o.number, p.name,
    o.total,
    round(coalesce(pay.paid, 0) * o.exchange_rate, 2),
    greatest(round(o.total - coalesce(pay.paid, 0) * o.exchange_rate, 2), 0),
    round(coalesce(pay.cash, 0) * o.exchange_rate, 2),
    round(coalesce(pay.card, 0) * o.exchange_rate, 2),
    round(coalesce(pay.biopago, 0) * o.exchange_rate, 2),
    greatest(round(o.total - coalesce(pay.paid, 0) * o.exchange_rate, 2), 0)
  from public.orders o
  left join public.parties p on p.id = o.party_id and p.org_id = o.org_id
  left join (
    select order_id,
      sum(amount) filter (where method = 'cash') as cash,
      sum(amount) filter (where method = 'card') as card,
      sum(amount) filter (where method = 'biopago') as biopago,
      sum(amount) as paid
    from public.order_payments
    where org_id = p_org_id
    group by order_id
  ) pay on pay.order_id = o.id
  where o.org_id = p_org_id
    and o.created_at >= v_close.opened_at
    and o.created_at <= coalesce(v_close.closed_at, now())
    and not exists (
      select 1 from public.cash_close_transactions t
      where t.org_id = p_org_id and t.source = 'order' and t.source_id = o.id
    );

  select
    coalesce(sum(total_ves), 0),
    coalesce(sum(paid_ves), 0),
    coalesce(sum(balance_ves), 0),
    coalesce(sum(cash_ves), 0),
    coalesce(sum(card_ves), 0),
    coalesce(sum(biopago_ves), 0),
    coalesce(sum(credit_ves), 0),
    count(*)
  into v_total, v_paid, v_balance, v_cash, v_card, v_biopago, v_credit, v_tx_count
  from public.cash_close_transactions
  where org_id = p_org_id and cash_close_id = p_cash_close_id;

  update public.cash_closes
  set status = 'closed', closed_at = now(), closed_by = auth.uid()
  where id = p_cash_close_id;

  return jsonb_build_object(
    'cash_close_id', p_cash_close_id,
    'number', v_close.number,
    'opened_at', v_close.opened_at,
    'closed_at', now(),
    'transactions', v_tx_count,
    'total_ves', v_total,
    'paid_ves', v_paid,
    'balance_ves', v_balance,
    'cash_ves', v_cash,
    'card_ves', v_card,
    'biopago_ves', v_biopago,
    'credit_ves', v_credit
  );
end;
$$;

grant execute on function public.cresko_close_cash_register(uuid, uuid) to authenticated;

-- 4) Vista en VES.
create or replace view public.cash_close_transactions_view
with (security_invoker = on) as

-- 1) Transacciones capturadas (snapshot) de cuadres cerrados (ya en VES).
select
  cc.id as cash_close_id,
  cc.org_id,
  s.id,
  s.source,
  s.source_id,
  s.number,
  s.party_name,
  s.total_ves,
  s.paid_ves,
  s.balance_ves,
  s.cash_ves,
  s.card_ves,
  s.biopago_ves,
  s.credit_ves,
  s.created_at
from public.cash_closes cc
join public.cash_close_transactions s
  on s.org_id = cc.org_id and s.cash_close_id = cc.id

union all

-- 2) En vivo: facturas del cuadre abierto (en VES).
select
  cc.id as cash_close_id,
  cc.org_id,
  i.id,
  'invoice' as source,
  i.id as source_id,
  i.number,
  p.name as party_name,
  i.total as total_ves,
  round(coalesce(pay.paid, 0) * i.exchange_rate, 2) as paid_ves,
  greatest(round(i.total - coalesce(pay.paid, 0) * i.exchange_rate, 2), 0) as balance_ves,
  round(coalesce(pay.cash, 0) * i.exchange_rate, 2) as cash_ves,
  round(coalesce(pay.card, 0) * i.exchange_rate, 2) as card_ves,
  round(coalesce(pay.biopago, 0) * i.exchange_rate, 2) as biopago_ves,
  greatest(round(i.total - coalesce(pay.paid, 0) * i.exchange_rate, 2), 0) as credit_ves,
  i.created_at
from public.cash_closes cc
join public.invoices i
  on i.org_id = cc.org_id
 and i.created_at >= cc.opened_at
 and i.created_at <= coalesce(cc.closed_at, now())
left join public.parties p on p.id = i.party_id and p.org_id = i.org_id
left join (
  select invoice_id,
    coalesce(sum(amount) filter (where method = 'cash'), 0) as cash,
    coalesce(sum(amount) filter (where method = 'card'), 0) as card,
    coalesce(sum(amount) filter (where method = 'biopago'), 0) as biopago,
    coalesce(sum(amount), 0) as paid
  from public.payments
  group by invoice_id
) pay on pay.invoice_id = i.id
where cc.status = 'open'
  and not exists (
    select 1 from public.cash_close_transactions s
    where s.org_id = cc.org_id and s.cash_close_id = cc.id and s.source = 'invoice' and s.source_id = i.id
  )

union all

-- 3) En vivo: pedidos del cuadre abierto (en VES).
select
  cc.id as cash_close_id,
  cc.org_id,
  o.id,
  'order' as source,
  o.id as source_id,
  o.number,
  p.name as party_name,
  o.total as total_ves,
  round(coalesce(pay.paid, 0) * o.exchange_rate, 2) as paid_ves,
  greatest(round(o.total - coalesce(pay.paid, 0) * o.exchange_rate, 2), 0) as balance_ves,
  round(coalesce(pay.cash, 0) * o.exchange_rate, 2) as cash_ves,
  round(coalesce(pay.card, 0) * o.exchange_rate, 2) as card_ves,
  round(coalesce(pay.biopago, 0) * o.exchange_rate, 2) as biopago_ves,
  greatest(round(o.total - coalesce(pay.paid, 0) * o.exchange_rate, 2), 0) as credit_ves,
  o.created_at
from public.cash_closes cc
join public.orders o
  on o.org_id = cc.org_id
 and o.created_at >= cc.opened_at
 and o.created_at <= coalesce(cc.closed_at, now())
left join public.parties p on p.id = o.party_id and p.org_id = o.org_id
left join (
  select order_id,
    coalesce(sum(amount) filter (where method = 'cash'), 0) as cash,
    coalesce(sum(amount) filter (where method = 'card'), 0) as card,
    coalesce(sum(amount) filter (where method = 'biopago'), 0) as biopago,
    coalesce(sum(amount), 0) as paid
  from public.order_payments
  group by order_id
) pay on pay.order_id = o.id
where cc.status = 'open'
  and not exists (
    select 1 from public.cash_close_transactions s
    where s.org_id = cc.org_id and s.cash_close_id = cc.id and s.source = 'order' and s.source_id = o.id
  );