-- =====================================================================
-- La cuenta del administrador del portal es intocable:
-- - cresko_admin_set_status() rechaza cambios sobre la organización del
--   portal admin (la que pertenece a un usuario en admin_users).
-- - cresko_admin_list_orgs() expone una columna `protected` para que el
--   panel la marque y deshabilite sus controles.
-- =====================================================================

-- =====================================================================
-- Actualizar estado de cuenta (solo portal admin) — protege al admin.
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

  -- La organización del portal admin no se puede modificar.
  if exists (
    select 1
    from public.organizations o
    join public.admin_users au on au.user_id = o.created_by
    where o.id = p_org_id
  ) then
    raise exception 'the administrator account is protected';
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
-- Listado del portal admin: expone si la cuenta es la del administrador.
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
  time_left interval,
  protected boolean
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
    end,
    exists (
      select 1 from public.admin_users au where au.user_id = o.created_by
    )
  from public.organizations o
  join auth.users u on u.id = o.created_by
  left join public.org_accounts a on a.org_id = o.id
  order by o.created_at desc;
end;
$$;