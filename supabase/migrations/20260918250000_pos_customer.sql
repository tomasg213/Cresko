create or replace function public.cresko_create_customer(
  p_org_id uuid,
  p_name text,
  p_document_type text default 'other',
  p_document_id text default null,
  p_phone text default null,
  p_email text default null
) returns public.parties
language plpgsql
security definer
set search_path = public
as $$
declare
  v_party public.parties;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not (
    public.has_permission(p_org_id, 'sales.checkout')
    or public.has_permission(p_org_id, 'catalog.write')
  ) then
    raise exception 'insufficient permissions';
  end if;

  insert into public.parties (
    org_id, name, document_type, document_id, phone, email, is_customer, created_by
  )
  values (
    p_org_id, p_name,
    coalesce(nullif(p_document_type, ''), 'other'),
    nullif(p_document_id, ''),
    nullif(p_phone, ''),
    nullif(p_email, ''),
    true,
    auth.uid()
  )
  returning * into v_party;

  return v_party;
end;
$$;

grant execute on function public.cresko_create_customer(uuid, text, text, text, text, text) to authenticated;