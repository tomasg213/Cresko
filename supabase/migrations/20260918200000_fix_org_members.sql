create or replace function public.cresko_org_members(p_org_id uuid)
returns table (
  id uuid,
  org_id uuid,
  user_id uuid,
  email text,
  role_id uuid,
  role_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'members.manage') then
    raise exception 'insufficient permissions';
  end if;

  return query
  select m.id, m.org_id, m.user_id, u.email::text, m.role_id, r.name
  from public.memberships m
  join public.auth_users_view u on u.id = m.user_id
  join public.org_roles r on r.id = m.role_id and r.org_id = m.org_id
  where m.org_id = p_org_id
  order by u.email;
end;
$$;