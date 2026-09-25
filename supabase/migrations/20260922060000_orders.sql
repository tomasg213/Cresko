-- =====================================================================
-- Pedidos: productos bajo pedido de clientes.
--
-- Un pedido registra la solicitud de un producto específico por un
-- cliente registrado, con cantidad, costo del pedido y moneda. Puede
-- pagarse total o parcialmente (el saldo queda como cuenta por cobrar),
-- de forma similar a la facturación. Los pedidos no mueven inventario.
-- =====================================================================

alter table public.document_sequences
  drop constraint if exists document_sequences_kind_check;
alter table public.document_sequences
  add constraint document_sequences_kind_check
  check (kind in ('po', 'gr', 'purchase', 'order'));

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  number text not null,
  party_id uuid not null,
  variant_id uuid not null,
  qty numeric(18, 3) not null check (qty > 0),
  unit_cost numeric(18, 2) not null check (unit_cost >= 0),
  unit_price numeric(18, 2) not null check (unit_price >= 0),
  subtotal numeric(18, 2) not null check (subtotal >= 0),
  tax numeric(18, 2) not null default 0 check (tax >= 0),
  total numeric(18, 2) not null check (total >= 0),
  currency text not null check (currency in ('VES', 'USD')),
  exchange_rate numeric(18, 6) not null check (exchange_rate > 0),
  tax_rate numeric(5, 2) not null default 0 check (tax_rate >= 0),
  status text not null default 'pending'
    check (status in ('pending', 'partial', 'paid', 'cancelled')),
  paid_amount numeric(18, 2) not null default 0 check (paid_amount >= 0),
  payment_method text check (payment_method in ('cash', 'card', 'transfer', 'credit')),
  expected_at date,
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, number),
  unique (id, org_id),
  constraint orders_party_same_org foreign key (party_id, org_id)
    references public.parties (id, org_id),
  constraint orders_variant_same_org foreign key (variant_id, org_id)
    references public.product_variants (id, org_id)
);

create index orders_org_idx on public.orders (org_id, created_at desc);
create trigger orders_set_updated_at before update on public.orders
  for each row execute function public.set_updated_at();

-- =====================================================================
-- Crear pedido. El monto pagado se aplica en el mismo momento; el saldo
-- restante queda como cuenta por cobrar del cliente.
-- =====================================================================

create or replace function public.cresko_create_order(
  p_org_id uuid,
  p_party_id uuid,
  p_variant_id uuid,
  p_qty numeric,
  p_unit_cost numeric,
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

  if p_qty is null or p_qty <= 0 then
    raise exception 'quantity must be positive';
  end if;
  if p_unit_cost is null or p_unit_cost < 0 then
    raise exception 'unit cost must not be negative';
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
  if p_payment_method not in ('cash', 'card', 'transfer', 'credit') then
    raise exception 'unsupported payment method';
  end if;

  if not exists (
    select 1 from public.parties
    where org_id = p_org_id and id = p_party_id and is_customer
  ) then
    raise exception 'customer not found';
  end if;
  if not exists (
    select 1 from public.product_variants
    where org_id = p_org_id and id = p_variant_id
  ) then
    raise exception 'product not found';
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
    org_id, number, party_id, variant_id, qty, unit_cost, unit_price,
    subtotal, tax, total, currency, exchange_rate, tax_rate,
    status, paid_amount, payment_method, expected_at, notes, created_by
  )
  values (
    p_org_id, format('PED-%s', lpad(v_number::text, 8, '0')), p_party_id, p_variant_id,
    p_qty, p_unit_cost, p_unit_price, v_subtotal, v_tax, v_total,
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

-- =====================================================================
-- Aplicar pago/abono a un pedido. El pedido no puede estar cancelado ni
-- pagado en su totalidad.
-- =====================================================================

create or replace function public.cresko_pay_order(
  p_org_id uuid,
  p_order_id uuid,
  p_amount numeric,
  p_method text default 'cash'
) returns public.orders
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

  update public.orders
  set paid_amount = v_new_paid,
      status = case when v_new_paid >= total then 'paid' else 'partial' end
  where id = v_order.id
  returning * into v_order;

  return v_order;
end;
$$;

-- =====================================================================
-- Anular pedido (solo si no tiene pagos registrados).
-- =====================================================================

create or replace function public.cresko_cancel_order(
  p_org_id uuid,
  p_order_id uuid
) returns public.orders
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
    raise exception 'order is already cancelled';
  end if;
  if v_order.paid_amount > 0 then
    raise exception 'no se puede anular un pedido con pagos';
  end if;

  update public.orders set status = 'cancelled' where id = v_order.id
  returning * into v_order;

  return v_order;
end;
$$;

-- =====================================================================
-- Vista de pedidos con cliente, producto y saldo por cobrar
-- =====================================================================

create view public.order_receivables
with (security_invoker = on) as
select
  o.org_id,
  o.id as order_id,
  o.number,
  o.party_id,
  p.name as party_name,
  o.variant_id,
  v.name as variant_name,
  v.sku as variant_sku,
  o.currency,
  o.total,
  o.paid_amount,
  (o.total - o.paid_amount) as balance,
  o.status,
  o.created_at
from public.orders o
join public.parties p on p.id = o.party_id and p.org_id = o.org_id
join public.product_variants v on v.id = o.variant_id and v.org_id = o.org_id;

-- =====================================================================
-- Pagos de pedidos
-- =====================================================================

create table public.order_payments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  order_id uuid not null,
  amount numeric(18, 2) not null check (amount > 0),
  currency text not null check (currency in ('VES', 'USD')),
  exchange_rate numeric(18, 6) not null check (exchange_rate > 0),
  method text not null check (method in ('cash', 'card', 'transfer')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (id, org_id),
  constraint order_payments_order_same_org foreign key (order_id, org_id)
    references public.orders (id, org_id)
);

create index order_payments_org_idx on public.order_payments (org_id, order_id);

-- =====================================================================
-- RLS
-- =====================================================================

alter table public.orders enable row level security;
alter table public.order_payments enable row level security;

create policy orders_member_read on public.orders for select
  to authenticated using (public.is_org_member(org_id));
create policy orders_member_write on public.orders for insert
  to authenticated with check (public.is_org_member(org_id));
create policy orders_admin_update on public.orders for update
  to authenticated
  using (public.has_permission(org_id, 'sales.checkout'))
  with check (public.has_permission(org_id, 'sales.checkout'));

create policy order_payments_member_read on public.order_payments for select
  to authenticated using (public.is_org_member(org_id));
create policy order_payments_member_write on public.order_payments for insert
  to authenticated with check (public.is_org_member(org_id));

revoke all on public.orders from anon;
revoke all on public.order_payments from anon;

grant select, insert, update on public.orders to authenticated;
grant select, insert on public.order_payments to authenticated;
grant select on public.order_receivables to authenticated;

grant execute on function public.cresko_create_order(
  uuid, uuid, uuid, numeric, numeric, numeric, text, numeric, numeric, numeric, text, date, text
) to authenticated;
grant execute on function public.cresko_pay_order(uuid, uuid, numeric, text) to authenticated;
grant execute on function public.cresko_cancel_order(uuid, uuid) to authenticated;