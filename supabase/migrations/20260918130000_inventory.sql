create or replace function public.is_org_stock_keeper(target_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.memberships
    where memberships.org_id = target_org_id
      and memberships.user_id = auth.uid()
      and memberships.role in ('owner', 'admin', 'warehouse')
  );
$$;

create table public.stock_levels (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  variant_id uuid not null,
  warehouse_id uuid not null,
  qty numeric(18, 3) not null default 0 check (qty >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, variant_id, warehouse_id),
  unique (id, org_id),
  constraint stock_levels_variant_same_org foreign key (variant_id, org_id)
    references public.product_variants (id, org_id),
  constraint stock_levels_warehouse_same_org foreign key (warehouse_id, org_id)
    references public.warehouses (id, org_id)
);

create index stock_levels_org_idx on public.stock_levels (org_id, warehouse_id);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  variant_id uuid not null,
  warehouse_id uuid not null,
  movement_type text not null
    check (movement_type in ('in', 'out', 'adjust', 'transfer_in', 'transfer_out', 'sale', 'purchase_receipt')),
  qty numeric(18, 3) not null check (qty <> 0),
  balance_after numeric(18, 3) not null check (balance_after >= 0),
  reference_type text,
  reference_id uuid,
  reason text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (id, org_id),
  constraint stock_movements_variant_same_org foreign key (variant_id, org_id)
    references public.product_variants (id, org_id),
  constraint stock_movements_warehouse_same_org foreign key (warehouse_id, org_id)
    references public.warehouses (id, org_id)
);

create index stock_movements_org_idx on public.stock_movements (org_id, created_at desc);
create index stock_movements_variant_idx on public.stock_movements (org_id, variant_id, warehouse_id, created_at desc);

create trigger stock_levels_set_updated_at before update on public.stock_levels
  for each row execute function public.set_updated_at();

create or replace function public.cresko_adjust_stock(
  p_org_id uuid,
  p_variant_id uuid,
  p_warehouse_id uuid,
  p_delta numeric,
  p_reason text default null
) returns public.stock_movements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level public.stock_levels;
  v_previous numeric;
  v_new_balance numeric;
  v_movement public.stock_movements;
begin
  if not public.is_org_stock_keeper(p_org_id) then
    raise exception 'insufficient permissions';
  end if;
  if p_delta = 0 then
    raise exception 'delta must not be zero';
  end if;

  select * into v_level
  from public.stock_levels
  where org_id = p_org_id
    and variant_id = p_variant_id
    and warehouse_id = p_warehouse_id
  for update;

  if v_level.id is null then
    v_previous := 0;
    insert into public.stock_levels (org_id, variant_id, warehouse_id, qty)
    values (p_org_id, p_variant_id, p_warehouse_id, 0)
    returning * into v_level;
  else
    v_previous := v_level.qty;
  end if;

  v_new_balance := v_previous + p_delta;
  if v_new_balance < 0 then
    raise exception 'insufficient stock';
  end if;

  update public.stock_levels
  set qty = v_new_balance
  where id = v_level.id;

  insert into public.stock_movements (
    org_id, variant_id, warehouse_id, movement_type, qty, balance_after, reason, created_by
  )
  values (
    p_org_id, p_variant_id, p_warehouse_id, 'adjust', p_delta, v_new_balance, p_reason, auth.uid()
  )
  returning * into v_movement;

  return v_movement;
end;
$$;

alter table public.stock_levels enable row level security;
alter table public.stock_movements enable row level security;

create policy stock_levels_member_read on public.stock_levels for select
  to authenticated using (public.is_org_member(org_id));

create policy stock_movements_member_read on public.stock_movements for select
  to authenticated using (public.is_org_member(org_id));

revoke all on public.stock_levels from anon;
revoke all on public.stock_movements from anon;

grant select on public.stock_levels to authenticated;
grant select on public.stock_movements to authenticated;
grant execute on function public.cresko_adjust_stock(uuid, uuid, uuid, numeric, text) to authenticated;
grant execute on function public.is_org_stock_keeper(uuid) to authenticated;