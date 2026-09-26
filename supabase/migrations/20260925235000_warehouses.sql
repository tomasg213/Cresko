-- =====================================================================
-- Sistema de almacenes completo:
-- - cresko_create_warehouse: crea un almacén (y su sucursal por defecto
--   si la organización aún no tiene ninguna).
-- - cresko_transfer_stock: traslada stock entre almacenes de la misma
--   empresa de forma atómica (transfer_out + transfer_in).
-- =====================================================================

create or replace function public.cresko_create_warehouse(
  p_org_id uuid,
  p_name text,
  p_code text
) returns public.warehouses
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch public.branches;
  v_warehouse public.warehouses;
begin
  if not public.has_permission(p_org_id, 'org.manage') then
    raise exception 'insufficient permissions';
  end if;

  select trim(p_name) into p_name;
  select upper(trim(p_code)) into p_code;
  if length(p_name) < 1 or length(p_name) > 120 then
    raise exception 'invalid warehouse name';
  end if;
  if length(p_code) < 1 or length(p_code) > 20 then
    raise exception 'invalid warehouse code';
  end if;

  -- Sucursal por defecto si la organización aún no tiene ninguna.
  select * into v_branch
  from public.branches
  where org_id = p_org_id and is_active = true
  order by created_at asc
  limit 1;

  if v_branch.id is null then
    insert into public.branches (org_id, name, code, is_active)
    values (p_org_id, 'Sucursal Principal', 'PRIN', true)
    returning * into v_branch;
  end if;

  insert into public.warehouses (org_id, branch_id, name, code, is_active)
  values (p_org_id, v_branch.id, p_name, p_code, true)
  returning * into v_warehouse;

  return v_warehouse;
end;
$$;

-- Traslado atómico de stock entre almacenes de la misma organización.
create or replace function public.cresko_transfer_stock(
  p_org_id uuid,
  p_variant_id uuid,
  p_from_warehouse_id uuid,
  p_to_warehouse_id uuid,
  p_qty numeric,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from_level public.stock_levels;
  v_to_level public.stock_levels;
  v_previous_from numeric;
  v_previous_to numeric;
  v_new_from numeric;
  v_new_to numeric;
  v_from_warehouse uuid;
  v_to_warehouse uuid;
begin
  if not public.has_permission(p_org_id, 'inventory.write') then
    raise exception 'insufficient permissions';
  end if;
  if p_from_warehouse_id = p_to_warehouse_id then
    raise exception 'origin and destination must differ';
  end if;
  if p_qty <= 0 then
    raise exception 'quantity must be positive';
  end if;

  -- Validar que ambos almacenes pertenezcan a la misma organización.
  select id into v_from_warehouse
  from public.warehouses
  where id = p_from_warehouse_id and org_id = p_org_id and is_active = true;
  if v_from_warehouse is null then
    raise exception 'origin warehouse not found';
  end if;

  select id into v_to_warehouse
  from public.warehouses
  where id = p_to_warehouse_id and org_id = p_org_id and is_active = true;
  if v_to_warehouse is null then
    raise exception 'destination warehouse not found';
  end if;

  -- Bloquear ambos niveles en orden consistente para evitar deadlocks.
  select * into v_from_level
  from public.stock_levels
  where org_id = p_org_id
    and variant_id = p_variant_id
    and warehouse_id = p_from_warehouse_id
  for update;

  select * into v_to_level
  from public.stock_levels
  where org_id = p_org_id
    and variant_id = p_variant_id
    and warehouse_id = p_to_warehouse_id
  for update;

  if v_from_level.id is null then
    v_previous_from := 0;
    insert into public.stock_levels (org_id, variant_id, warehouse_id, qty)
    values (p_org_id, p_variant_id, p_from_warehouse_id, 0)
    returning * into v_from_level;
  else
    v_previous_from := v_from_level.qty;
  end if;

  v_new_from := v_previous_from - p_qty;
  if v_new_from < 0 then
    raise exception 'insufficient stock in origin warehouse';
  end if;

  update public.stock_levels
  set qty = v_new_from
  where id = v_from_level.id;

  insert into public.stock_movements (
    org_id, variant_id, warehouse_id, movement_type, qty, balance_after, reference_type, reference_id, reason, created_by
  )
  values (
    p_org_id, p_variant_id, p_from_warehouse_id, 'transfer_out', -p_qty, v_new_from,
    'transfer', p_to_warehouse_id, p_reason, auth.uid()
  );

  if v_to_level.id is null then
    v_previous_to := 0;
    insert into public.stock_levels (org_id, variant_id, warehouse_id, qty)
    values (p_org_id, p_variant_id, p_to_warehouse_id, 0)
    returning * into v_to_level;
  else
    v_previous_to := v_to_level.qty;
  end if;

  v_new_to := v_previous_to + p_qty;

  update public.stock_levels
  set qty = v_new_to
  where id = v_to_level.id;

  insert into public.stock_movements (
    org_id, variant_id, warehouse_id, movement_type, qty, balance_after, reference_type, reference_id, reason, created_by
  )
  values (
    p_org_id, p_variant_id, p_to_warehouse_id, 'transfer_in', p_qty, v_new_to,
    'transfer', p_from_warehouse_id, p_reason, auth.uid()
  );
end;
$$;

grant execute on function public.cresko_create_warehouse(uuid, text, text) to authenticated;
grant execute on function public.cresko_transfer_stock(uuid, uuid, uuid, uuid, numeric, text) to authenticated;