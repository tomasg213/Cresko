create table public.document_sequences (
  org_id uuid not null references public.organizations(id) on delete cascade,
  kind text not null check (kind in ('po', 'gr', 'purchase')),
  last_number bigint not null default 0,
  primary key (org_id, kind)
);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  supplier_id uuid not null,
  warehouse_id uuid not null,
  number text not null,
  status text not null default 'ordered'
    check (status in ('draft', 'ordered', 'partial', 'received', 'void')),
  currency text not null check (currency in ('VES', 'USD')),
  exchange_rate numeric(18, 6) not null check (exchange_rate > 0),
  tax_rate numeric(5, 2) not null default 0 check (tax_rate >= 0),
  expected_at date,
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, number),
  unique (id, org_id),
  constraint purchase_orders_supplier_same_org foreign key (supplier_id, org_id)
    references public.parties (id, org_id),
  constraint purchase_orders_warehouse_same_org foreign key (warehouse_id, org_id)
    references public.warehouses (id, org_id)
);

create index purchase_orders_org_idx on public.purchase_orders (org_id, created_at desc);

create table public.po_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  po_id uuid not null,
  variant_id uuid not null,
  qty_ordered numeric(18, 3) not null check (qty_ordered > 0),
  qty_received numeric(18, 3) not null default 0 check (qty_received >= 0),
  unit_cost numeric(18, 2) not null check (unit_cost >= 0),
  line_total numeric(18, 2) not null check (line_total >= 0),
  currency text not null check (currency in ('VES', 'USD')),
  created_at timestamptz not null default now(),
  unique (id, org_id),
  constraint po_lines_po_same_org foreign key (po_id, org_id)
    references public.purchase_orders (id, org_id),
  constraint po_lines_variant_same_org foreign key (variant_id, org_id)
    references public.product_variants (id, org_id)
);

create index po_lines_org_idx on public.po_lines (org_id, po_id);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  po_id uuid not null,
  number text not null,
  received_at date not null default current_date,
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (org_id, number),
  unique (id, org_id),
  constraint goods_receipts_po_same_org foreign key (po_id, org_id)
    references public.purchase_orders (id, org_id)
);

create index goods_receipts_org_idx on public.goods_receipts (org_id, po_id);

create table public.receipt_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  receipt_id uuid not null,
  po_line_id uuid not null,
  variant_id uuid not null,
  qty numeric(18, 3) not null check (qty > 0),
  unit_cost numeric(18, 2) not null check (unit_cost >= 0),
  line_total numeric(18, 2) not null check (line_total >= 0),
  currency text not null check (currency in ('VES', 'USD')),
  created_at timestamptz not null default now(),
  unique (id, org_id),
  constraint receipt_lines_receipt_same_org foreign key (receipt_id, org_id)
    references public.goods_receipts (id, org_id),
  constraint receipt_lines_po_line_same_org foreign key (po_line_id, org_id)
    references public.po_lines (id, org_id),
  constraint receipt_lines_variant_same_org foreign key (variant_id, org_id)
    references public.product_variants (id, org_id)
);

create index receipt_lines_org_idx on public.receipt_lines (org_id, receipt_id);

create table public.supplier_invoices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  supplier_id uuid not null,
  po_id uuid,
  number text not null,
  subtotal numeric(18, 2) not null check (subtotal >= 0),
  tax numeric(18, 2) not null default 0 check (tax >= 0),
  total numeric(18, 2) not null check (total >= 0),
  currency text not null check (currency in ('VES', 'USD')),
  exchange_rate numeric(18, 6) not null check (exchange_rate > 0),
  tax_rate numeric(5, 2) not null default 0 check (tax_rate >= 0),
  status text not null default 'posted' check (status in ('posted', 'void')),
  due_date date,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, number),
  unique (id, org_id),
  constraint supplier_invoices_supplier_same_org foreign key (supplier_id, org_id)
    references public.parties (id, org_id),
  constraint supplier_invoices_po_same_org foreign key (po_id, org_id)
    references public.purchase_orders (id, org_id)
);

create index supplier_invoices_org_idx on public.supplier_invoices (org_id, created_at desc);

create table public.ap_ledger (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  party_id uuid not null,
  supplier_invoice_id uuid not null,
  entry_type text not null check (entry_type in ('charge', 'payment', 'reversal')),
  amount numeric(18, 2) not null check (amount <> 0),
  currency text not null check (currency in ('VES', 'USD')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (id, org_id),
  constraint ap_ledger_party_same_org foreign key (party_id, org_id)
    references public.parties (id, org_id),
  constraint ap_ledger_invoice_same_org foreign key (supplier_invoice_id, org_id)
    references public.supplier_invoices (id, org_id)
);

create index ap_ledger_org_idx on public.ap_ledger (org_id, party_id, created_at desc);

create table public.replenishment_config (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  variant_id uuid not null,
  warehouse_id uuid not null,
  min_qty numeric(18, 3) not null default 0 check (min_qty >= 0),
  max_qty numeric(18, 3) not null default 0 check (max_qty >= 0),
  pack_multiple numeric(18, 3) not null default 1 check (pack_multiple > 0),
  preferred_supplier_id uuid,
  lead_time_days integer not null default 0 check (lead_time_days >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, variant_id, warehouse_id),
  unique (id, org_id),
  constraint replenishment_config_variant_same_org foreign key (variant_id, org_id)
    references public.product_variants (id, org_id),
  constraint replenishment_config_warehouse_same_org foreign key (warehouse_id, org_id)
    references public.warehouses (id, org_id),
  constraint replenishment_config_supplier_same_org foreign key (preferred_supplier_id, org_id)
    references public.parties (id, org_id)
);

create index replenishment_config_org_idx on public.replenishment_config (org_id, warehouse_id);

create trigger purchase_orders_set_updated_at before update on public.purchase_orders
  for each row execute function public.set_updated_at();
create trigger supplier_invoices_set_updated_at before update on public.supplier_invoices
  for each row execute function public.set_updated_at();
create trigger replenishment_config_set_updated_at before update on public.replenishment_config
  for each row execute function public.set_updated_at();

create or replace function public.cresko_create_purchase_order(
  p_org_id uuid,
  p_supplier_id uuid,
  p_warehouse_id uuid,
  p_currency text,
  p_exchange_rate numeric,
  p_tax_rate numeric,
  p_lines jsonb,
  p_expected_at date default null,
  p_notes text default null
) returns public.purchase_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.member_role;
  v_number bigint;
  v_po public.purchase_orders;
  v_line jsonb;
  v_qty numeric;
  v_cost numeric(18, 2);
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;

  select role into v_role from public.memberships
  where org_id = p_org_id and user_id = auth.uid();
  if v_role is null or v_role not in ('owner', 'admin', 'purchasing') then
    raise exception 'insufficient permissions';
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

  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'po', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_number;

  insert into public.purchase_orders (
    org_id, supplier_id, warehouse_id, number, status, currency,
    exchange_rate, tax_rate, expected_at, notes, created_by
  )
  values (
    p_org_id, p_supplier_id, p_warehouse_id, format('POC-%s', lpad(v_number::text, 8, '0')),
    'ordered', p_currency, p_exchange_rate, p_tax_rate, p_expected_at, p_notes, auth.uid()
  )
  returning * into v_po;

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
  v_role public.member_role;
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
  v_inv_number bigint;
  v_supplier_invoice_id uuid;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;

  select role into v_role from public.memberships
  where org_id = p_org_id and user_id = auth.uid();
  if v_role is null or v_role not in ('owner', 'admin', 'purchasing', 'warehouse') then
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
    p_org_id, v_po.supplier_id, v_supplier_invoice_id, 'charge', v_total, v_po.currency, auth.uid()
  );

  return v_receipt;
end;
$$;

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
  v_role public.member_role;
  v_invoice public.invoices;
  v_payment public.payments;
  v_amount numeric(18, 2) := round(p_amount, 2);
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;

  select role into v_role from public.memberships
  where org_id = p_org_id and user_id = auth.uid();
  if v_role is null or v_role not in ('owner', 'admin', 'cashier') then
    raise exception 'insufficient permissions';
  end if;

  if v_amount <= 0 then
    raise exception 'payment must be positive';
  end if;
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select * into v_invoice from public.invoices
  where org_id = p_org_id and id = p_invoice_id;
  if v_invoice.id is null then
    raise exception 'invoice not found';
  end if;
  if v_invoice.currency <> p_currency then
    raise exception 'currency mismatch';
  end if;

  insert into public.payments (
    org_id, invoice_id, amount, currency, exchange_rate, method, created_by
  )
  values (
    p_org_id, v_invoice.id, v_amount, p_currency, v_invoice.exchange_rate, p_method, auth.uid()
  )
  returning * into v_payment;

  insert into public.ar_ledger (
    org_id, party_id, invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_invoice.party_id, v_invoice.id, 'payment', -v_amount, p_currency, auth.uid()
  );

  return v_payment;
end;
$$;

create or replace function public.cresko_pay_supplier(
  p_org_id uuid,
  p_party_id uuid,
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
  v_role public.member_role;
  v_invoice public.supplier_invoices;
  v_ledger public.ap_ledger;
  v_amount numeric(18, 2) := round(p_amount, 2);
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;

  select role into v_role from public.memberships
  where org_id = p_org_id and user_id = auth.uid();
  if v_role is null or v_role not in ('owner', 'admin', 'purchasing') then
    raise exception 'insufficient permissions';
  end if;

  if v_amount <= 0 then
    raise exception 'payment must be positive';
  end if;
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select * into v_invoice from public.supplier_invoices
  where org_id = p_org_id and id = p_supplier_invoice_id;
  if v_invoice.id is null then
    raise exception 'supplier invoice not found';
  end if;
  if v_invoice.currency <> p_currency then
    raise exception 'currency mismatch';
  end if;

  insert into public.ap_ledger (
    org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, p_party_id, v_invoice.id, 'payment', -v_amount, p_currency, auth.uid()
  )
  returning * into v_ledger;

  return v_ledger;
end;
$$;

create or replace function public.cresko_replenishment_needed(
  p_org_id uuid
) returns table (
  variant_id uuid,
  variant_name text,
  variant_sku text,
  warehouse_id uuid,
  warehouse_name text,
  on_hand numeric,
  on_order numeric,
  min_qty numeric,
  max_qty numeric,
  pack_multiple numeric,
  suggested_qty numeric,
  preferred_supplier_id uuid
)
language plpgsql
security invoker
set search_path = public
as $$
begin
  return query
  select
    r.variant_id,
    v.name,
    v.sku,
    r.warehouse_id,
    w.name,
    coalesce(s.qty, 0),
    coalesce(o.qty, 0),
    r.min_qty,
    r.max_qty,
    r.pack_multiple,
    ceil((r.max_qty - coalesce(s.qty, 0) - coalesce(o.qty, 0)) / r.pack_multiple) * r.pack_multiple,
    r.preferred_supplier_id
  from public.replenishment_config r
  join public.product_variants v on v.id = r.variant_id and v.org_id = r.org_id
  join public.warehouses w on w.id = r.warehouse_id and w.org_id = r.org_id
  left join public.stock_levels s
    on s.org_id = r.org_id and s.variant_id = r.variant_id and s.warehouse_id = r.warehouse_id
  left join (
    select pl.variant_id, po.warehouse_id, sum(pl.qty_ordered - pl.qty_received) as qty
    from public.po_lines pl
    join public.purchase_orders po on po.id = pl.po_id and po.org_id = pl.org_id
    where po.org_id = p_org_id and po.status in ('ordered', 'partial')
    group by pl.variant_id, po.warehouse_id
  ) o
    on o.variant_id = r.variant_id and o.warehouse_id = r.warehouse_id
  where r.org_id = p_org_id
    and r.is_active
    and r.max_qty > 0
    and (coalesce(s.qty, 0) + coalesce(o.qty, 0)) < r.min_qty;
end;
$$;

create view public.ar_balances
with (security_invoker = on) as
select org_id, party_id, currency, sum(amount) as balance
from public.ar_ledger
group by org_id, party_id, currency;

create view public.ap_balances
with (security_invoker = on) as
select org_id, party_id, currency, sum(amount) as balance
from public.ap_ledger
group by org_id, party_id, currency;

alter table public.purchase_orders enable row level security;
alter table public.po_lines enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.receipt_lines enable row level security;
alter table public.supplier_invoices enable row level security;
alter table public.ap_ledger enable row level security;
alter table public.replenishment_config enable row level security;

create policy purchase_orders_member_read on public.purchase_orders for select
  to authenticated using (public.is_org_member(org_id));
create policy po_lines_member_read on public.po_lines for select
  to authenticated using (public.is_org_member(org_id));
create policy goods_receipts_member_read on public.goods_receipts for select
  to authenticated using (public.is_org_member(org_id));
create policy receipt_lines_member_read on public.receipt_lines for select
  to authenticated using (public.is_org_member(org_id));
create policy supplier_invoices_member_read on public.supplier_invoices for select
  to authenticated using (public.is_org_member(org_id));
create policy ap_ledger_member_read on public.ap_ledger for select
  to authenticated using (public.is_org_member(org_id));
create policy replenishment_config_member_read on public.replenishment_config for select
  to authenticated using (public.is_org_member(org_id));
create policy replenishment_config_admin_write on public.replenishment_config for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

revoke all on public.purchase_orders from anon;
revoke all on public.po_lines from anon;
revoke all on public.goods_receipts from anon;
revoke all on public.receipt_lines from anon;
revoke all on public.supplier_invoices from anon;
revoke all on public.ap_ledger from anon;
revoke all on public.replenishment_config from anon;
revoke all on public.document_sequences from anon;

grant select on public.purchase_orders to authenticated;
grant select on public.po_lines to authenticated;
grant select on public.goods_receipts to authenticated;
grant select on public.receipt_lines to authenticated;
grant select on public.supplier_invoices to authenticated;
grant select on public.ap_ledger to authenticated;
grant select, insert, update, delete on public.replenishment_config to authenticated;
grant select on public.ar_balances to authenticated;
grant select on public.ap_balances to authenticated;
grant execute on function public.cresko_create_purchase_order(
  uuid, uuid, uuid, text, numeric, numeric, jsonb, date, text
) to authenticated;
grant execute on function public.cresko_receive_goods(
  uuid, uuid, jsonb, date, text
) to authenticated;
grant execute on function public.cresko_receive_payment(
  uuid, uuid, uuid, numeric, text, text
) to authenticated;
grant execute on function public.cresko_pay_supplier(
  uuid, uuid, uuid, numeric, text, text
) to authenticated;
grant execute on function public.cresko_replenishment_needed(uuid) to authenticated;