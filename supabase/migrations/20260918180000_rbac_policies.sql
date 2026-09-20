create policy organizations_update_admin on public.organizations for update
  to authenticated
  using (public.has_permission(id, 'org.manage'))
  with check (public.has_permission(id, 'org.manage'));

create policy branches_admin_write on public.branches for all
  to authenticated
  using (public.has_permission(org_id, 'org.manage'))
  with check (public.has_permission(org_id, 'org.manage'));

create policy warehouses_admin_write on public.warehouses for all
  to authenticated
  using (public.has_permission(org_id, 'org.manage'))
  with check (public.has_permission(org_id, 'org.manage'));