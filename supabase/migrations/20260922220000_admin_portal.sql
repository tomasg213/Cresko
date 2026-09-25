-- =====================================================================
-- Portal de administración de cuentas de clientes.
--
-- - organizations.access_status: 'active' | 'suspended' (controla el
--   acceso a la app; suspendida bloquea el login/uso).
-- - org_accounts: estado de pago manual por organización
--   ('paid' | 'free' | 'pending') con notas.
-- - admin_users: quiénes son administradores del portal.
-- =====================================================================

alter table public.organizations
  add column access_status text not null default 'active'
  check (access_status in ('active', 'suspended'));

create table public.org_accounts (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  payment_status text not null default 'pending'
    check (payment_status in ('paid', 'free', 'pending')),
  notes text,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

create table public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

insert into public.admin_users (user_id)
select id from auth.users where email = 'tomasg1337@gmail.com'
on conflict do nothing;

create or replace function public.cresko_is_portal_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid());
$$;

-- =====================================================================
-- Listar organizaciones con estado de cuenta (solo portal admin)
-- =====================================================================

create or replace function public.cresko_admin_list_orgs()
returns table (
  org_id uuid,
  org_name text,
  owner_email text,
  owner_name text,
  created_at timestamptz,
  member_count bigint,
  access_status text,
  payment_status text,
  notes text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.cresko_is_portal_admin() then
    raise exception 'administrator access denied';
  end if;
  return query
  select
    o.id,
    o.name,
    u.email::text,
    coalesce(u.raw_user_meta_data ->> 'name', '')::text,
    o.created_at,
    (select count(*) from public.memberships m where m.org_id = o.id),
    o.access_status,
    coalesce(a.payment_status, 'pending'),
    a.notes
  from public.organizations o
  join auth.users u on u.id = o.created_by
  left join public.org_accounts a on a.org_id = o.id
  order by o.created_at desc;
end;
$$;

-- =====================================================================
-- Actualizar estado de cuenta de una organización (solo portal admin)
-- =====================================================================

create or replace function public.cresko_admin_set_status(
  p_org_id uuid,
  p_access_status text default null,
  p_payment_status text default null,
  p_notes text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.cresko_is_portal_admin() then
    raise exception 'administrator access denied';
  end if;

  if p_access_status is not null then
    if p_access_status not in ('active', 'suspended') then
      raise exception 'invalid access status';
    end if;
    update public.organizations set access_status = p_access_status where id = p_org_id;
  end if;

  if p_payment_status is not null or p_notes is not null then
    insert into public.org_accounts (org_id, payment_status, notes, updated_by, updated_at)
    values (
      p_org_id,
      coalesce(p_payment_status, 'pending'),
      p_notes,
      auth.uid(),
      now()
    )
    on conflict (org_id) do update set
      payment_status = coalesce(excluded.payment_status, public.org_accounts.payment_status),
      notes = excluded.notes,
      updated_by = excluded.updated_by,
      updated_at = now();
  end if;
end;
$$;

-- =====================================================================
-- RLS
-- =====================================================================

alter table public.org_accounts enable row level security;
alter table public.admin_users enable row level security;

create policy admin_users_read on public.admin_users for select
  to authenticated using (public.cresko_is_portal_admin());
create policy admin_users_write on public.admin_users for all
  to authenticated using (public.cresko_is_portal_admin())
  with check (public.cresko_is_portal_admin());

create policy org_accounts_admin_read on public.org_accounts for select
  to authenticated using (public.cresko_is_portal_admin());
create policy org_accounts_admin_write on public.org_accounts for all
  to authenticated using (public.cresko_is_portal_admin())
  with check (public.cresko_is_portal_admin());

-- El estado de acceso lo lee cualquier miembro (para que la app bloquee).
create policy organizations_read_access_status on public.organizations for select
  to authenticated using (public.is_org_member(id));

revoke all on public.org_accounts from anon;
revoke all on public.admin_users from anon;

grant select on public.org_accounts to authenticated;
grant select on public.admin_users to authenticated;

grant execute on function public.cresko_is_portal_admin() to authenticated;
grant execute on function public.cresko_admin_list_orgs() to authenticated;
grant execute on function public.cresko_admin_set_status(uuid, text, text, text) to authenticated;