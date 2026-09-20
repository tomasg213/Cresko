create table public.parties (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 180),
  document_type text not null default 'other' check (document_type in ('rif', 'ci', 'passport', 'other')),
  document_id text,
  phone text,
  email text,
  is_customer boolean not null default false,
  is_supplier boolean not null default false,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, org_id)
);

create index parties_org_idx on public.parties (org_id, is_customer, is_active);
create index parties_lookup_idx on public.parties (org_id, lower(name));

create table public.invoice_sequences (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  last_number bigint not null default 0
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  number text not null,
  party_id uuid,
  subtotal numeric(18, 2) not null check (subtotal >= 0),
  tax numeric(18, 2) not null default 0 check (tax >= 0),
  total numeric(18, 2) not null check (total >= 0),
  currency text not null check (currency in ('VES', 'USD')),
  exchange_rate numeric(18, 6) not null check (exchange_rate > 0),
  tax_rate numeric(5, 2) not null default 0 check (tax_rate >= 0),
  status text not null default 'posted' check (status in ('posted', 'void')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, number),
  unique (id, org_id),
  constraint invoices_party_same_org foreign key (party_id, org_id)
    references public.parties (id, org_id)
);

create index invoices_org_idx on public.invoices (org_id, created_at desc);

create table public.invoice_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  variant_id uuid not null,
  qty numeric(18, 3) not null check (qty > 0),
  unit_price numeric(18, 2) not null check (unit_price >= 0),
  line_total numeric(18, 2) not null check (line_total >= 0),
  tax numeric(18, 2) not null default 0 check (tax >= 0),
  currency text not null check (currency in ('VES', 'USD')),
  created_at timestamptz not null default now(),
  unique (id, org_id),
  constraint invoice_lines_invoice_same_org foreign key (invoice_id, org_id)
    references public.invoices (id, org_id),
  constraint invoice_lines_variant_same_org foreign key (variant_id, org_id)
    references public.product_variants (id, org_id)
);

create index invoice_lines_org_idx on public.invoice_lines (org_id, invoice_id);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  amount numeric(18, 2) not null check (amount > 0),
  currency text not null check (currency in ('VES', 'USD')),
  exchange_rate numeric(18, 6) not null check (exchange_rate > 0),
  method text not null check (method in ('cash', 'card', 'transfer', 'credit')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (id, org_id),
  constraint payments_invoice_same_org foreign key (invoice_id, org_id)
    references public.invoices (id, org_id)
);

create index payments_org_idx on public.payments (org_id, invoice_id);

create table public.ar_ledger (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  party_id uuid not null,
  invoice_id uuid not null,
  entry_type text not null check (entry_type in ('charge', 'payment', 'reversal')),
  amount numeric(18, 2) not null check (amount <> 0),
  currency text not null check (currency in ('VES', 'USD')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (id, org_id),
  constraint ar_ledger_party_same_org foreign key (party_id, org_id)
    references public.parties (id, org_id),
  constraint ar_ledger_invoice_same_org foreign key (invoice_id, org_id)
    references public.invoices (id, org_id)
);

create index ar_ledger_org_idx on public.ar_ledger (org_id, party_id, created_at desc);

create trigger parties_set_updated_at before update on public.parties
  for each row execute function public.set_updated_at();
create trigger invoices_set_updated_at before update on public.invoices
  for each row execute function public.set_updated_at();

create or replace function public.cresko_checkout(
  p_org_id uuid,
  p_warehouse_id uuid,
  p_price_list_code text,
  p_currency text,
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
  v_role public.member_role;
  v_list_id uuid;
  v_number bigint;
  v_invoice public.invoices;
  v_line jsonb;
  v_price numeric(18, 2);
  v_qty numeric(18, 3);
  v_line_total numeric(18, 2);
  v_line_tax numeric(18, 2);
  v_subtotal numeric(18, 2) := 0;
  v_tax numeric(18, 2) := 0;
  v_total numeric(18, 2);
  v_balance numeric(18, 2);
  v_level public.stock_levels;
  v_party_id uuid;
  v_invoice_id uuid;
  v_lines_count int := 0;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;

  select role into v_role
  from public.memberships
  where org_id = p_org_id and user_id = auth.uid();

  if v_role is null or v_role not in ('owner', 'admin', 'cashier') then
    raise exception 'insufficient permissions';
  end if;

  if p_currency not in ('VES', 'USD') then
    raise exception 'unsupported currency';
  end if;
  if p_exchange_rate <= 0 then
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

    select amount into v_price
    from public.variant_prices
    where org_id = p_org_id
      and variant_id = (v_line ->> 'variant_id')::uuid
      and price_list_id = v_list_id
      and currency = p_currency;
    if v_price is null then
      raise exception 'no price for variant % in list % / %', v_line ->> 'variant_id', p_price_list_code, p_currency;
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

    v_line_total := round(v_price * v_qty, 2);
    v_line_tax := round(v_line_total * p_tax_rate / 100, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_tax := v_tax + v_line_tax;
    v_lines_count := v_lines_count + 1;
  end loop;

  v_total := round(v_subtotal + v_tax, 2);
  v_balance := round(v_total - p_paid_amount, 2);

  if v_balance < 0 then
    raise exception 'payment exceeds total';
  end if;
  if v_balance > 0 and v_party_id is null then
    raise exception 'credit sale requires a party';
  end if;

  insert into public.invoices (
    org_id, number, party_id, subtotal, tax, total,
    currency, exchange_rate, tax_rate, status, created_by
  )
  values (
    p_org_id, format('FAC-%s', lpad(v_number::text, 8, '0')), v_party_id,
    v_subtotal, v_tax, v_total, p_currency, p_exchange_rate, p_tax_rate, 'posted', auth.uid()
  )
  returning * into v_invoice;
  v_invoice_id := v_invoice.id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_qty := (v_line ->> 'qty')::numeric;
    select amount into v_price
    from public.variant_prices
    where org_id = p_org_id
      and variant_id = (v_line ->> 'variant_id')::uuid
      and price_list_id = v_list_id
      and currency = p_currency;

    v_line_total := round(v_price * v_qty, 2);
    v_line_tax := round(v_line_total * p_tax_rate / 100, 2);

    insert into public.invoice_lines (
      org_id, invoice_id, variant_id, qty, unit_price, line_total, tax, currency
    )
    values (
      p_org_id, v_invoice_id, (v_line ->> 'variant_id')::uuid,
      v_qty, v_price, v_line_total, v_line_tax, p_currency
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

  if p_paid_amount > 0 then
    insert into public.payments (
      org_id, invoice_id, amount, currency, exchange_rate, method, created_by
    )
    values (
      p_org_id, v_invoice_id, round(p_paid_amount, 2), p_currency, p_exchange_rate,
      p_payment_method, auth.uid()
    );
  end if;

  if v_balance > 0 then
    insert into public.ar_ledger (
      org_id, party_id, invoice_id, entry_type, amount, currency, created_by
    )
    values (
      p_org_id, v_party_id, v_invoice_id, 'charge', v_balance, p_currency, auth.uid()
    );
  end if;

  return v_invoice;
end;
$$;

alter table public.parties enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_lines enable row level security;
alter table public.payments enable row level security;
alter table public.ar_ledger enable row level security;

create policy parties_member_read on public.parties for select
  to authenticated using (public.is_org_member(org_id));
create policy parties_admin_write on public.parties for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

create policy invoices_member_read on public.invoices for select
  to authenticated using (public.is_org_member(org_id));
create policy invoice_lines_member_read on public.invoice_lines for select
  to authenticated using (public.is_org_member(org_id));
create policy payments_member_read on public.payments for select
  to authenticated using (public.is_org_member(org_id));
create policy ar_ledger_member_read on public.ar_ledger for select
  to authenticated using (public.is_org_member(org_id));

revoke all on public.parties from anon;
revoke all on public.invoices from anon;
revoke all on public.invoice_lines from anon;
revoke all on public.payments from anon;
revoke all on public.ar_ledger from anon;
revoke all on public.invoice_sequences from anon;

grant select, insert, update, delete on public.parties to authenticated;
grant select on public.invoices to authenticated;
grant select on public.invoice_lines to authenticated;
grant select on public.payments to authenticated;
grant select on public.ar_ledger to authenticated;
grant execute on function public.cresko_checkout(
  uuid, uuid, text, text, numeric, numeric, jsonb, text, numeric, uuid, jsonb
) to authenticated;