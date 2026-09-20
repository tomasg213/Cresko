create extension if not exists pgcrypto;

create type public.member_role as enum (
  'owner',
  'admin',
  'cashier',
  'warehouse',
  'purchasing'
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  legal_name text,
  tax_id text,
  default_currency text not null default 'VES' check (default_currency in ('VES', 'USD')),
  timezone text not null default 'America/Caracas',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.member_role not null default 'cashier',
  created_at timestamptz not null default now(),
  unique (org_id, user_id)
);

create index memberships_user_idx on public.memberships (user_id, org_id);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  code text not null,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, code),
  unique (id, org_id)
);

create index branches_org_idx on public.branches (org_id, is_active);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  name text not null check (length(trim(name)) between 1 and 120),
  code text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, code),
  unique (id, org_id),
  constraint warehouses_branch_same_org foreign key (branch_id, org_id)
    references public.branches (id, org_id)
);

create index warehouses_org_idx on public.warehouses (org_id, is_active);

create or replace function public.is_org_member(target_org_id uuid)
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
  );
$$;

create or replace function public.is_org_admin(target_org_id uuid)
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
      and memberships.role in ('owner', 'admin')
  );
$$;

alter table public.organizations enable row level security;
alter table public.memberships enable row level security;
alter table public.branches enable row level security;
alter table public.warehouses enable row level security;

create policy organizations_select_member
  on public.organizations for select
  to authenticated
  using (public.is_org_member(id));

create policy organizations_insert_creator
  on public.organizations for insert
  to authenticated
  with check (created_by = auth.uid());

create policy organizations_update_admin
  on public.organizations for update
  to authenticated
  using (public.is_org_admin(id))
  with check (public.is_org_admin(id));

create policy memberships_select_member
  on public.memberships for select
  to authenticated
  using (public.is_org_member(org_id));

create policy memberships_insert_self_owner
  on public.memberships for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and role = 'owner'
    and (
      public.is_org_member(org_id)
      or exists (
        select 1
        from public.organizations
        where organizations.id = org_id
          and organizations.created_by = auth.uid()
      )
    )
  );

create policy memberships_manage_admin
  on public.memberships for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

create policy branches_member_read
  on public.branches for select
  to authenticated
  using (public.is_org_member(org_id));

create policy branches_admin_write
  on public.branches for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

create policy warehouses_member_read
  on public.warehouses for select
  to authenticated
  using (public.is_org_member(org_id));

create policy warehouses_admin_write
  on public.warehouses for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

revoke all on public.organizations from anon;
revoke all on public.memberships from anon;
revoke all on public.branches from anon;
revoke all on public.warehouses from anon;

grant select, insert, update on public.organizations to authenticated;
grant select, insert, update, delete on public.memberships to authenticated;
grant select, insert, update, delete on public.branches to authenticated;
grant select, insert, update, delete on public.warehouses to authenticated;
