-- =====================================================================
-- Transacciones de un cuadre de caja.
--
-- Para un cuadre cerrado se usan las transacciones capturadas (snapshot).
-- Para un cuadre abierto se calculan en vivo las facturas y pedidos del
-- rango (opened_at..now) con su desglose por método de pago, de modo que
-- el detalle siempre muestre lo facturado hasta el momento.
-- =====================================================================

create or replace view public.cash_close_transactions_view
with (security_invoker = on) as

-- 1) Transacciones capturadas (snapshot) de cuadres cerrados.
select
  cc.id as cash_close_id,
  cc.org_id,
  s.id,
  s.source,
  s.source_id,
  s.number,
  s.party_name,
  s.total_usd,
  s.paid_usd,
  s.balance_usd,
  s.cash_usd,
  s.card_usd,
  s.biopago_usd,
  s.credit_usd,
  s.created_at
from public.cash_closes cc
join public.cash_close_transactions s
  on s.org_id = cc.org_id and s.cash_close_id = cc.id

union all

-- 2) En vivo: facturas del cuadre abierto (rango opened_at..now).
select
  cc.id as cash_close_id,
  cc.org_id,
  i.id,
  'invoice' as source,
  i.id as source_id,
  i.number,
  p.name as party_name,
  round(i.total / i.exchange_rate, 2) as total_usd,
  coalesce(pay.paid, 0) as paid_usd,
  greatest(round(i.total / i.exchange_rate, 2) - coalesce(pay.paid, 0), 0) as balance_usd,
  coalesce(pay.cash, 0) as cash_usd,
  coalesce(pay.card, 0) as card_usd,
  coalesce(pay.biopago, 0) as biopago_usd,
  greatest(round(i.total / i.exchange_rate, 2) - coalesce(pay.paid, 0), 0) as credit_usd,
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

-- 3) En vivo: pedidos del cuadre abierto (rango opened_at..now).
select
  cc.id as cash_close_id,
  cc.org_id,
  o.id,
  'order' as source,
  o.id as source_id,
  o.number,
  p.name as party_name,
  round(o.total / o.exchange_rate, 2) as total_usd,
  coalesce(pay.paid, 0) as paid_usd,
  greatest(round(o.total / o.exchange_rate, 2) - coalesce(pay.paid, 0), 0) as balance_usd,
  coalesce(pay.cash, 0) as cash_usd,
  coalesce(pay.card, 0) as card_usd,
  coalesce(pay.biopago, 0) as biopago_usd,
  greatest(round(o.total / o.exchange_rate, 2) - coalesce(pay.paid, 0), 0) as credit_usd,
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