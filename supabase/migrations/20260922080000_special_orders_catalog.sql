-- =====================================================================
-- Pedidos: productos bajo pedido vinculados al catálogo.
--
-- Un "producto bajo pedido" DEBE existir en el catálogo: special_order_products
-- referencia product_variants (variant_id). El nombre/sku se derivan del
-- catálogo y el precio de venta es editable (por defecto el precio retail).
--
-- El costo total de un pedido se calcula como cantidad x precio de venta.
-- =====================================================================

drop view if exists public.order_receivables;
drop function if exists public.cresko_create_order(uuid, uuid, uuid, numeric, numeric, numeric, text, numeric, numeric, numeric, text, date, text);
drop function if exists public.cresko_pay_order(uuid, uuid, numeric, text);
drop function if exists public.cresko_cancel_order(uuid, uuid);
drop function if exists public.cresko_create_special_product(uuid, text, text, text, numeric, text);
drop table if exists public.order_payments;
drop table if exists public.orders;
drop table if exists public.special_order_products;

-- =====================================================================
-- Productos bajo pedido (referencian el catálogo)
-- =====================================================================

create table public.special_order_products (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  variant_id uuid not null,
  unit_price numeric(18, 2) not null default 0 check (unit_price >= 0),
  currency text not null default 'USD' check (currency in ('VES', 'USD')),
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, variant_id),
  unique (id, org_id),
  constraint special_order_products_variant_same_org foreign key (variant_id, org_id)
    references public.product_variants (id, org_id)
);

create index special_order_products_org_idx on public.special_order_products (org_id, is_active);
create trigger special_order_products_set_updated_at before update on public.special_order_products
  for each row execute function public.set_updated_at();

-- =====================================================================
-- Pedidos de clientes sobre un producto bajo pedido
-- =====================================================================

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  number text not null,
  product_id uuid not null,
  party_id uuid not null,
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
  constraint orders_product_same_org foreign key (product_id, org_id)
    references public.special_order_products (id, org_id),
  constraint orders_party_same_org foreign key (party_id, org_id)
    references public.parties (id, org_id)
);

create index orders_org_idx on public.orders (org_id, created_at desc);
create index orders_product_idx on public.orders (org_id, product_id, created_at desc);
create trigger orders_set_updated_at before update on public.orders
  for each row execute function public.set_updated_at();

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
-- Crear producto bajo pedido (debe referenciar una variante del catálogo)
-- =====================================================================

create or replace function public.cresko_create_special_product(
  p_org_id uuid,
  p_variant_id uuid,
  p_unit_price numeric default null,
  p_currency text default 'USD'
) returns public.special_order_products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.special_order_products;
  v_retail numeric;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'catalog.write') then
    raise exception 'insufficient permissions';
  end if;

  if not exists (
    select 1 from public.product_variants
    where org_id = p_org_id and id = p_variant_id
  ) then
    raise exception 'variant must exist in catalog';
  end if;
  if p_currency not in ('VES', 'USD') then
    raise exception 'unsupported currency';
  end if;

  -- Precio por defecto: retail USD del catálogo.
  if p_unit_price is null then
    select vp.amount into v_retail
    from public.variant_prices vp
    join public.price_lists pl on pl.id = vp.price_list_id and pl.org_id = vp.org_id
    where vp.org_id = p_org_id and vp.variant_id = p_variant_id
      and pl.code = 'retail' and vp.currency = 'USD'
    order by vp.amount
    limit 1;
    p_unit_price := coalesce(v_retail, 0);
  end if;
  if p_unit_price < 0 then
    raise exception 'unit price must not be negative';
  end if;

  insert into public.special_order_products (
    org_id, variant_id, unit_price, currency, created_by
  )
  values (p_org_id, p_variant_id, p_unit_price, p_currency, auth.uid())
  returning * into v_product;

  return v_product;
end;
$$;

-- =====================================================================
-- Crear pedido: costo total = cantidad x precio de venta.
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

-- =====================================================================
-- Aplicar pago/abono a un pedido.
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
-- Vista de pedidos con cliente, producto bajo pedido y saldo
-- =====================================================================

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
  o.created_at
from public.orders o
join public.special_order_products sp on sp.id = o.product_id and sp.org_id = o.org_id
join public.product_variants v on v.id = sp.variant_id and v.org_id = sp.org_id
join public.parties p on p.id = o.party_id and p.org_id = o.org_id;

-- =====================================================================
-- RLS
-- =====================================================================

alter table public.special_order_products enable row level security;
alter table public.orders enable row level security;
alter table public.order_payments enable row level security;

create policy special_order_products_member_read on public.special_order_products for select
  to authenticated using (public.is_org_member(org_id));
create policy special_order_products_member_write on public.special_order_products for insert
  to authenticated with check (public.is_org_member(org_id));
create policy special_order_products_admin_update on public.special_order_products for update
  to authenticated
  using (public.has_permission(org_id, 'catalog.write'))
  with check (public.has_permission(org_id, 'catalog.write'));

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

revoke all on public.special_order_products from anon;
revoke all on public.orders from anon;
revoke all on public.order_payments from anon;

grant select, insert, update on public.special_order_products to authenticated;
grant select, insert, update on public.orders to authenticated;
grant select, insert on public.order_payments to authenticated;
grant select on public.order_receivables to authenticated;

grant execute on function public.cresko_create_special_product(
  uuid, uuid, numeric, text
) to authenticated;
grant execute on function public.cresko_create_order(
  uuid, uuid, uuid, numeric, numeric, text, numeric, numeric, numeric, text, date, text
) to authenticated;
grant execute on function public.cresko_pay_order(uuid, uuid, numeric, text) to authenticated;
grant execute on function public.cresko_cancel_order(uuid, uuid) to authenticated;