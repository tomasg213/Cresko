-- =====================================================================
-- Pedidos: estado de entrega.
--
-- Cada pedido tiene dos estados independientes:
--  - Cobro: pending (por cobrar), partial (abonado), paid (pagado), cancelled.
--  - Entrega: pending (por entregar), delivered (entregado).
--
-- Reglas:
--  - Al entregar un pedido con saldo pendiente, queda como "entregado"
--    y el saldo pasa a cuenta por cobrar (se mantiene visible en
--    order_receivables).
--  - Al entregar un pedido ya pagado, el pedido se elimina.
--  - Al pagar por completo un pedido entregado, el pedido se elimina.
--  - Los pagos de un pedido eliminado también se eliminan.
-- =====================================================================

alter table public.orders
  add column delivery_status text not null default 'pending'
  check (delivery_status in ('pending', 'delivered'));

drop function if exists public.cresko_pay_order(uuid, uuid, numeric, text);

-- =====================================================================
-- Pagar/abonar pedido. Si queda pagado y el pedido ya fue entregado,
-- el pedido y sus pagos se eliminan (la cuenta por cobrar queda saldada).
-- =====================================================================

create or replace function public.cresko_pay_order(
  p_org_id uuid,
  p_order_id uuid,
  p_amount numeric,
  p_method text default 'cash'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_amount numeric(18, 2) := round(p_amount, 2);
  v_new_paid numeric(18, 2);
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
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select * into v_order from public.orders
  where org_id = p_org_id and id = p_order_id;
  if v_order.id is null then
    raise exception 'order not found';
  end if;
  if v_order.status = 'cancelled' then
    raise exception 'order is cancelled';
  end if;
  if v_order.status = 'paid' then
    raise exception 'order is already paid';
  end if;

  v_new_paid := round(v_order.paid_amount + v_amount, 2);
  if v_new_paid > v_order.total then
    raise exception 'El monto no puede ser mayor que toda la deuda';
  end if;

  insert into public.order_payments (
    org_id, order_id, amount, currency, exchange_rate, method, created_by
  )
  values (
    p_org_id, v_order.id, v_amount, v_order.currency, v_order.exchange_rate,
    p_method, auth.uid()
  );

  -- Pedido entregado y ahora pagado por completo: se elimina.
  if v_order.delivery_status = 'delivered' and v_new_paid >= v_order.total then
    delete from public.order_payments
    where org_id = p_org_id and order_id = v_order.id;
    delete from public.orders
    where org_id = p_org_id and id = v_order.id;
    return;
  end if;

  update public.orders
  set paid_amount = v_new_paid,
      status = case when v_new_paid >= total then 'paid' else 'partial' end
  where org_id = p_org_id and id = v_order.id;
end;
$$;

-- =====================================================================
-- Entregar pedido. Si ya estaba pagado, se elimina. Si queda saldo,
-- pasa a cuenta por cobrar y el pedido queda como entregado.
-- =====================================================================

create or replace function public.cresko_deliver_order(
  p_org_id uuid,
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'sales.checkout') then
    raise exception 'insufficient permissions';
  end if;

  select * into v_order from public.orders
  where org_id = p_org_id and id = p_order_id;
  if v_order.id is null then
    raise exception 'order not found';
  end if;
  if v_order.status = 'cancelled' then
    raise exception 'order is cancelled';
  end if;
  if v_order.delivery_status = 'delivered' then
    raise exception 'order is already delivered';
  end if;

  -- Ya pagado y se entrega: se elimina.
  if v_order.paid_amount >= v_order.total then
    delete from public.order_payments
    where org_id = p_org_id and order_id = v_order.id;
    delete from public.orders
    where org_id = p_org_id and id = v_order.id;
    return;
  end if;

  -- Con saldo pendiente: queda entregado y su saldo pasa a cuenta por cobrar.
  update public.orders
  set delivery_status = 'delivered'
  where org_id = p_org_id and id = v_order.id;
end;
$$;

-- =====================================================================
-- Vista de pedidos con estado de entrega
-- =====================================================================

drop view if exists public.order_receivables;

create view public.order_receivables
with (security_invoker = on) as
select
  o.org_id,
  o.id as order_id,
  o.number,
  o.product_id,
  v.name as product_name,
  v.sku as product_sku,
  o.party_id,
  p.name as party_name,
  o.currency,
  o.total,
  o.paid_amount,
  (o.total - o.paid_amount) as balance,
  o.status,
  o.delivery_status,
  o.created_at
from public.orders o
join public.special_order_products sp on sp.id = o.product_id and sp.org_id = o.org_id
join public.product_variants v on v.id = sp.variant_id and v.org_id = sp.org_id
join public.parties p on p.id = o.party_id and p.org_id = o.org_id;

grant execute on function public.cresko_pay_order(uuid, uuid, numeric, text) to authenticated;
grant execute on function public.cresko_deliver_order(uuid, uuid) to authenticated;