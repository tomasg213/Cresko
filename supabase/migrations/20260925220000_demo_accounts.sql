-- =====================================================================
-- Separación de cuentas demo (expiran a las 24h) y cuentas permanentes.
--
-- - organizations.is_demo: marca cuentas creadas desde el portal de
--   prueba. Las permanentes quedan en false.
-- - organizations.demo_expires_at: momento en que la demo expira.
--   NULL para cuentas permanentes.
-- - cresko_expire_demos(): suspende demos vencidas (access_status =
--   'suspended'). Se ejecuta perezosamente al acceder a una org.
-- - cresko_is_demo_expired(p_org_id): estado efectivo de expiración.
-- - cresko_admin_list_orgs() ahora incluye is_demo y el tiempo restante.
-- =====================================================================

alter table public.organizations
  add column is_demo boolean not null default false,
  add column demo_expires_at timestamptz;

create index organizations_demo_expiry_idx
  on public.organizations (is_demo, demo_expires_at)
  where is_demo;

-- Suspende las demos que ya vencieron.
create or replace function public.cresko_expire_demos()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.organizations
    set access_status = 'suspended',
        updated_at = now()
  where is_demo
    and demo_expires_at is not null
    and demo_expires_at < now()
    and access_status <> 'suspended';
end;
$$;

-- Estado efectivo de una organización: las demos vencidas cuentan como
-- suspendidas aunque el registro aún esté en 'active'.
create or replace function public.cresko_is_demo_expired(p_org_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_demo boolean;
  v_expires_at timestamptz;
begin
  select o.is_demo, o.demo_expires_at
    into v_is_demo, v_expires_at
  from public.organizations o
  where o.id = p_org_id;

  return coalesce(v_is_demo, false)
    and v_expires_at is not null
    and v_expires_at < now();
end;
$$;

-- =====================================================================
-- Reemplaza la vista del portal admin para separar demos y permanentes.
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
  notes text,
  is_demo boolean,
  demo_expires_at timestamptz,
  time_left interval
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
    case
      when o.is_demo and o.demo_expires_at is not null and o.demo_expires_at < now()
        then 'suspended'
      else o.access_status
    end,
    coalesce(a.payment_status, 'pending'),
    a.notes,
    coalesce(o.is_demo, false),
    o.demo_expires_at,
    case
      when o.is_demo and o.demo_expires_at is not null then o.demo_expires_at - now()
      else null
    end
  from public.organizations o
  join auth.users u on u.id = o.created_by
  left join public.org_accounts a on a.org_id = o.id
  order by o.created_at desc;
end;
$$;

-- =====================================================================
-- La API lee el estado efectivo de la org de un miembro: si es una demo
-- vencida, el valor devuelto es 'suspended' (y la expira perezosamente).
-- =====================================================================

create or replace function public.cresko_org_access_status(p_org_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if p_org_id is null then
    return null;
  end if;

  select o.access_status
    into v_status
  from public.organizations o
  where o.id = p_org_id;

  if v_status is null then
    return null;
  end if;

  if public.cresko_is_demo_expired(p_org_id) then
    perform public.cresko_expire_demos();
    return 'suspended';
  end if;

  return v_status;
end;
$$;

grant execute on function public.cresko_expire_demos() to authenticated;
grant execute on function public.cresko_is_demo_expired(uuid) to authenticated;
grant execute on function public.cresko_org_access_status(uuid) to authenticated;

-- Auto-suspensión cada hora de demos vencidas (pg_cron).
create extension if not exists pg_cron;
select cron.schedule(
  'cresko-expire-demos',
  '0 * * * *',
  'select public.cresko_expire_demos()'
);

-- Backfill: las organizaciones creadas por correos demo (@cresko.preview)
-- antes de esta migración se marcan como demo con expiración retroactiva.
update public.organizations o
set is_demo = true,
    demo_expires_at = coalesce(o.demo_expires_at, o.created_at + interval '24 hours'),
    access_status = case
      when o.created_at + interval '24 hours' < now() then 'suspended'
      else o.access_status
    end
from auth.users u
where u.id = o.created_by
  and u.email like '%@cresko.preview'
  and o.is_demo = false;