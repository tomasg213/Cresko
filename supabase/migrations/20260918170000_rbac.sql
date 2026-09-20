-- =====================================================================
-- RBAC: permisos, roles personalizados, membresías por rol e invitaciones
-- =====================================================================

create table public.permissions (
  code text primary key,
  description text not null default ''
);

insert into public.permissions (code, description) values
  ('org.manage', 'Administrar configuración del comercio'),
  ('members.manage', 'Administrar miembros e invitaciones'),
  ('roles.manage', 'Administrar roles y sus permisos'),
  ('catalog.read', 'Ver catálogo de artículos'),
  ('catalog.write', 'Crear y editar artículos y precios'),
  ('inventory.read', 'Ver inventario y movimientos'),
  ('inventory.write', 'Registrar ajustes de inventario'),
  ('sales.read', 'Ver ventas y facturas'),
  ('sales.checkout', 'Realizar ventas en el punto de venta'),
  ('sales.credit', 'Vender a crédito (fiado)'),
  ('finance.read', 'Ver cuentas por cobrar y por pagar'),
  ('finance.receive', 'Registrar cobros a clientes'),
  ('finance.pay', 'Registrar pagos a proveedores'),
  ('purchasing.read', 'Ver órdenes de compra'),
  ('purchasing.write', 'Crear órdenes de compra'),
  ('purchasing.receive', 'Recibir mercancía de proveedores'),
  ('replenishment.read', 'Ver sugerencias de reposición'),
  ('replenishment.write', 'Configurar reposición');

create table public.org_roles (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  permissions text[] not null default '{}',
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, name),
  unique (id, org_id)
);

create index org_roles_org_idx on public.org_roles (org_id);

-- Migrar membresías del enum fijo a rol personalizado.
-- 1) Crear un rol sistema "Administrador" con todos los permisos por organización.
insert into public.org_roles (org_id, name, permissions, is_system)
select id, 'Administrador', array(select code from public.permissions), true
from public.organizations;

-- 2) Columna role_id sobre las membresías existentes.
alter table public.memberships add column role_id uuid;

update public.memberships m
set role_id = r.id
from public.org_roles r
where r.org_id = m.org_id and r.is_system;

alter table public.memberships alter column role_id set not null;
alter table public.memberships add constraint memberships_role_same_org
  foreign key (role_id, org_id) references public.org_roles (id, org_id);

-- 3) Quitar el enum fijo y sus dependencias de políticas.
drop policy if exists memberships_insert_self_owner on public.memberships;
drop policy if exists memberships_manage_admin on public.memberships;
drop policy if exists organizations_update_admin on public.organizations;
drop policy if exists branches_admin_write on public.branches;
drop policy if exists warehouses_admin_write on public.warehouses;
drop policy if exists categories_admin_write on public.categories;
drop policy if exists brands_admin_write on public.brands;
drop policy if exists products_admin_write on public.products;
drop policy if exists product_variants_admin_write on public.product_variants;
drop policy if exists barcodes_admin_write on public.barcodes;
drop policy if exists price_lists_admin_write on public.price_lists;
drop policy if exists variant_prices_admin_write on public.variant_prices;
drop policy if exists parties_admin_write on public.parties;
drop policy if exists replenishment_config_admin_write on public.replenishment_config;

drop function if exists public.is_org_admin(uuid);
drop function if exists public.is_org_stock_keeper(uuid);

alter table public.memberships drop column role;
drop type if exists public.member_role;

-- =====================================================================
-- Funciones de permiso
-- =====================================================================

create or replace function public.has_permission(target_org_id uuid, perm text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.memberships m
    join public.org_roles r on r.id = m.role_id and r.org_id = m.org_id
    where m.org_id = target_org_id
      and m.user_id = auth.uid()
      and perm = any (r.permissions)
  );
$$;

-- =====================================================================
-- Invitaciones
-- =====================================================================

create table public.org_invitations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  email text not null,
  role_id uuid not null,
  token uuid not null default gen_random_uuid(),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'revoked')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  unique (org_id, email),
  unique (id, org_id),
  constraint org_invitations_role_same_org foreign key (role_id, org_id)
    references public.org_roles (id, org_id)
);

create index org_invitations_org_idx on public.org_invitations (org_id, status);
create index org_invitations_token_idx on public.org_invitations (token);

create or replace function public.cresko_accept_invitation(p_token uuid)
returns public.memberships
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.org_invitations;
  v_membership public.memberships;
  v_user_email text;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select email into v_user_email from auth.users where id = auth.uid();

  select * into v_inv
  from public.org_invitations
  where token = p_token and status = 'pending';

  if v_inv.id is null then
    raise exception 'invalid or expired invitation';
  end if;
  if lower(coalesce(v_user_email, '')) <> lower(v_inv.email) then
    raise exception 'invitation does not match this account';
  end if;

  insert into public.memberships (org_id, user_id, role_id)
  values (v_inv.org_id, auth.uid(), v_inv.role_id)
  on conflict (org_id, user_id) do update set role_id = excluded.role_id
  returning * into v_membership;

  update public.org_invitations
  set status = 'accepted', accepted_at = now()
  where id = v_inv.id;

  return v_membership;
end;
$$;

-- Listado de miembros con correo y rol, restringido a administradores de miembros.
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
  select m.id, m.org_id, m.user_id, u.email, m.role_id, r.name
  from public.memberships m
  join public.auth_users_view u on u.id = m.user_id
  join public.org_roles r on r.id = m.role_id and r.org_id = m.org_id
  where m.org_id = p_org_id
  order by u.email;
end;
$$;

-- Vista de miembros que expone el correo desde auth.users (solo la usa la función definer).
create or replace view public.auth_users_view as
  select id, email from auth.users;

-- =====================================================================
-- Actualizar funciones de dominio a permisos
-- =====================================================================

create or replace function public.cresko_create_product(
  p_org_id uuid,
  p_name text,
  p_variants jsonb,
  p_category_id uuid default null,
  p_brand_id uuid default null,
  p_base_unit text default 'unit',
  p_description text default null
) returns public.products
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_product public.products;
  v_variant jsonb;
  v_barcode jsonb;
  v_price jsonb;
  v_variant_id uuid;
  v_list_id uuid;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'catalog.write') then
    raise exception 'insufficient permissions';
  end if;

  insert into public.price_lists (org_id, code, name)
  values
    (p_org_id, 'retail', 'Detal'),
    (p_org_id, 'wholesale', 'Mayor')
  on conflict (org_id, code) do nothing;

  insert into public.products (
    org_id, name, description, category_id, brand_id, base_unit, created_by
  )
  values (
    p_org_id, p_name, p_description, p_category_id, p_brand_id, p_base_unit, auth.uid()
  )
  returning * into v_product;

  for v_variant in select value from jsonb_array_elements(p_variants)
  loop
    insert into public.product_variants (org_id, product_id, sku, name, attributes)
    values (
      p_org_id,
      v_product.id,
      coalesce(nullif(v_variant ->> 'sku', ''), gen_random_uuid()::text),
      coalesce(nullif(v_variant ->> 'name', ''), p_name),
      coalesce(v_variant -> 'attributes', '{}'::jsonb)
    )
    returning id into v_variant_id;

    for v_barcode in
      select value from jsonb_array_elements(coalesce(v_variant -> 'barcodes', '[]'::jsonb))
    loop
      insert into public.barcodes (org_id, variant_id, barcode, format, is_primary)
      values (
        p_org_id,
        v_variant_id,
        v_barcode ->> 'barcode',
        coalesce(nullif(v_barcode ->> 'format', ''), 'EAN13'),
        coalesce((v_barcode ->> 'is_primary')::boolean, false)
      );
    end loop;

    for v_price in
      select value from jsonb_array_elements(coalesce(v_variant -> 'prices', '[]'::jsonb))
    loop
      select id into v_list_id
      from public.price_lists
      where org_id = p_org_id and code = v_price ->> 'price_list_code';

      if v_list_id is null then
        raise exception 'price list not found: %', v_price ->> 'price_list_code';
      end if;

      insert into public.variant_prices (org_id, variant_id, price_list_id, currency, amount)
      values (
        p_org_id,
        v_variant_id,
        v_list_id,
        v_price ->> 'currency',
        (v_price ->> 'amount')::numeric
      );
    end loop;
  end loop;

  return v_product;
end;
$$;

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
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'inventory.write') then
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
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'sales.checkout') then
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
  end loop;

  v_total := round(v_subtotal + v_tax, 2);
  v_balance := round(v_total - p_paid_amount, 2);

  if v_balance < 0 then
    raise exception 'payment exceeds total';
  end if;
  if v_balance > 0 and v_party_id is null then
    raise exception 'credit sale requires a party';
  end if;
  if v_balance > 0 and not public.has_permission(p_org_id, 'sales.credit') then
    raise exception 'insufficient permissions for credit sale';
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

create or replace function public.cresko_create_purchase_order(
  p_org_id uuid,
  p_supplier_id uuid,
  p_warehouse_id uuid,
  p_currency text,
  p_exchange_rate numeric,
  p_tax_rate numeric,
  p_lines jsonb,
  p_expected_at date default null,
  p_notes text default null
) returns public.purchase_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_number bigint;
  v_po public.purchase_orders;
  v_line jsonb;
  v_qty numeric;
  v_cost numeric(18, 2);
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'purchasing.write') then
    raise exception 'insufficient permissions';
  end if;

  if p_currency not in ('VES', 'USD') then
    raise exception 'unsupported currency';
  end if;
  if p_exchange_rate <= 0 then
    raise exception 'exchange rate must be positive';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    raise exception 'purchase order must have at least one line';
  end if;

  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'po', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_number;

  insert into public.purchase_orders (
    org_id, supplier_id, warehouse_id, number, status, currency,
    exchange_rate, tax_rate, expected_at, notes, created_by
  )
  values (
    p_org_id, p_supplier_id, p_warehouse_id, format('POC-%s', lpad(v_number::text, 8, '0')),
    'ordered', p_currency, p_exchange_rate, p_tax_rate, p_expected_at, p_notes, auth.uid()
  )
  returning * into v_po;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_qty := (v_line ->> 'qty')::numeric;
    v_cost := (v_line ->> 'unit_cost')::numeric;
    if v_qty <= 0 then
      raise exception 'quantity must be positive';
    end if;
    if v_cost < 0 then
      raise exception 'unit cost must not be negative';
    end if;

    insert into public.po_lines (
      org_id, po_id, variant_id, qty_ordered, qty_received,
      unit_cost, line_total, currency
    )
    values (
      p_org_id, v_po.id, (v_line ->> 'variant_id')::uuid, v_qty, 0,
      v_cost, round(v_cost * v_qty, 2), p_currency
    );
  end loop;

  return v_po;
end;
$$;

create or replace function public.cresko_receive_goods(
  p_org_id uuid,
  p_po_id uuid,
  p_lines jsonb,
  p_received_at date default current_date,
  p_notes text default null
) returns public.goods_receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_po public.purchase_orders;
  v_number bigint;
  v_receipt public.goods_receipts;
  v_line jsonb;
  v_po_line public.po_lines;
  v_qty numeric;
  v_receivable numeric;
  v_level public.stock_levels;
  v_subtotal numeric(18, 2) := 0;
  v_tax numeric(18, 2);
  v_total numeric(18, 2);
  v_inv_number bigint;
  v_supplier_invoice_id uuid;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'purchasing.receive') then
    raise exception 'insufficient permissions';
  end if;

  select * into v_po from public.purchase_orders
  where org_id = p_org_id and id = p_po_id;
  if v_po.id is null then
    raise exception 'purchase order not found';
  end if;
  if v_po.status in ('void', 'received') then
    raise exception 'purchase order cannot receive goods';
  end if;

  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'gr', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_number;

  insert into public.goods_receipts (org_id, po_id, number, received_at, notes, created_by)
  values (p_org_id, v_po.id, format('ENT-%s', lpad(v_number::text, 8, '0')), p_received_at, p_notes, auth.uid())
  returning * into v_receipt;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    select * into v_po_line
    from public.po_lines
    where org_id = p_org_id and id = (v_line ->> 'po_line_id')::uuid and po_id = v_po.id;
    if v_po_line.id is null then
      raise exception 'purchase order line not found';
    end if;

    v_qty := (v_line ->> 'qty')::numeric;
    if v_qty <= 0 then
      raise exception 'received quantity must be positive';
    end if;
    v_receivable := v_po_line.qty_ordered - v_po_line.qty_received;
    if v_qty > v_receivable then
      raise exception 'received quantity exceeds pending quantity';
    end if;

    insert into public.receipt_lines (
      org_id, receipt_id, po_line_id, variant_id, qty, unit_cost, line_total, currency
    )
    values (
      p_org_id, v_receipt.id, v_po_line.id, v_po_line.variant_id, v_qty,
      v_po_line.unit_cost, round(v_po_line.unit_cost * v_qty, 2), v_po_line.currency
    );

    update public.po_lines
    set qty_received = qty_received + v_qty
    where id = v_po_line.id;

    select * into v_level
    from public.stock_levels
    where org_id = p_org_id and variant_id = v_po_line.variant_id and warehouse_id = v_po.warehouse_id
    for update;

    if v_level.id is null then
      insert into public.stock_levels (org_id, variant_id, warehouse_id, qty)
      values (p_org_id, v_po_line.variant_id, v_po.warehouse_id, v_qty);
    else
      update public.stock_levels set qty = qty + v_qty where id = v_level.id;
    end if;

    insert into public.stock_movements (
      org_id, variant_id, warehouse_id, movement_type, qty, balance_after,
      reference_type, reference_id, created_by
    )
    values (
      p_org_id, v_po_line.variant_id, v_po.warehouse_id, 'purchase_receipt', v_qty,
      coalesce(v_level.qty, 0) + v_qty, 'goods_receipt', v_receipt.id, auth.uid()
    );

    v_subtotal := v_subtotal + round(v_po_line.unit_cost * v_qty, 2);
  end loop;

  update public.purchase_orders set
    status = case when exists (
      select 1 from public.po_lines
      where org_id = p_org_id and po_id = v_po.id and qty_received < qty_ordered
    ) then 'partial' else 'received' end
  where id = v_po.id;

  v_tax := round(v_subtotal * v_po.tax_rate / 100, 2);
  v_total := round(v_subtotal + v_tax, 2);

  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'purchase', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_inv_number;

  insert into public.supplier_invoices (
    org_id, supplier_id, po_id, number, subtotal, tax, total,
    currency, exchange_rate, tax_rate, status, due_date, created_by
  )
  values (
    p_org_id, v_po.supplier_id, v_po.id, format('CMP-%s', lpad(v_inv_number::text, 8, '0')),
    v_subtotal, v_tax, v_total, v_po.currency, v_po.exchange_rate, v_po.tax_rate,
    'posted', p_received_at, auth.uid()
  )
  returning id into v_supplier_invoice_id;

  insert into public.ap_ledger (
    org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_po.supplier_id, v_supplier_invoice_id, 'charge', v_total, v_po.currency, auth.uid()
  );

  return v_receipt;
end;
$$;

create or replace function public.cresko_receive_payment(
  p_org_id uuid,
  p_party_id uuid,
  p_invoice_id uuid,
  p_amount numeric,
  p_currency text,
  p_method text default 'cash'
) returns public.payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.invoices;
  v_payment public.payments;
  v_amount numeric(18, 2) := round(p_amount, 2);
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'finance.receive') then
    raise exception 'insufficient permissions';
  end if;

  if v_amount <= 0 then
    raise exception 'payment must be positive';
  end if;
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select * into v_invoice from public.invoices
  where org_id = p_org_id and id = p_invoice_id;
  if v_invoice.id is null then
    raise exception 'invoice not found';
  end if;
  if v_invoice.currency <> p_currency then
    raise exception 'currency mismatch';
  end if;

  insert into public.payments (
    org_id, invoice_id, amount, currency, exchange_rate, method, created_by
  )
  values (
    p_org_id, v_invoice.id, v_amount, p_currency, v_invoice.exchange_rate, p_method, auth.uid()
  )
  returning * into v_payment;

  insert into public.ar_ledger (
    org_id, party_id, invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_invoice.party_id, v_invoice.id, 'payment', -v_amount, p_currency, auth.uid()
  );

  return v_payment;
end;
$$;

create or replace function public.cresko_pay_supplier(
  p_org_id uuid,
  p_supplier_invoice_id uuid,
  p_amount numeric,
  p_currency text,
  p_method text default 'cash'
) returns public.ap_ledger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.supplier_invoices;
  v_ledger public.ap_ledger;
  v_amount numeric(18, 2) := round(p_amount, 2);
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'finance.pay') then
    raise exception 'insufficient permissions';
  end if;

  if v_amount <= 0 then
    raise exception 'payment must be positive';
  end if;
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select * into v_invoice from public.supplier_invoices
  where org_id = p_org_id and id = p_supplier_invoice_id;
  if v_invoice.id is null then
    raise exception 'supplier invoice not found';
  end if;
  if v_invoice.currency <> p_currency then
    raise exception 'currency mismatch';
  end if;

  insert into public.ap_ledger (
    org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_invoice.supplier_id, v_invoice.id, 'payment', -v_amount, p_currency, auth.uid()
  )
  returning * into v_ledger;

  return v_ledger;
end;
$$;

-- =====================================================================
-- RLS por permisos
-- =====================================================================

create policy memberships_insert_admin on public.memberships for insert
  to authenticated with check (
    public.has_permission(org_id, 'members.manage')
    or exists (
      select 1 from public.organizations o
      where o.id = org_id and o.created_by = auth.uid()
    )
  );
create policy memberships_update_admin on public.memberships for update
  to authenticated using (public.has_permission(org_id, 'members.manage'));
create policy memberships_delete_admin on public.memberships for delete
  to authenticated using (public.has_permission(org_id, 'members.manage'));

create policy org_roles_member_read on public.org_roles for select
  to authenticated using (public.is_org_member(org_id));
create policy org_roles_admin_write on public.org_roles for all
  to authenticated
  using (public.has_permission(org_id, 'roles.manage')
    or exists (select 1 from public.organizations o where o.id = org_id and o.created_by = auth.uid()))
  with check (public.has_permission(org_id, 'roles.manage')
    or exists (select 1 from public.organizations o where o.id = org_id and o.created_by = auth.uid()));

create policy org_invitations_member_read on public.org_invitations for select
  to authenticated using (
    public.has_permission(org_id, 'members.manage')
    or lower(email) = (select lower(u.email) from auth.users u where u.id = auth.uid())
  );
create policy org_invitations_admin_write on public.org_invitations for all
  to authenticated
  using (public.has_permission(org_id, 'members.manage'))
  with check (public.has_permission(org_id, 'members.manage'));

create policy categories_admin_write on public.categories for all
  to authenticated
  using (public.has_permission(org_id, 'catalog.write'))
  with check (public.has_permission(org_id, 'catalog.write'));

create policy brands_admin_write on public.brands for all
  to authenticated
  using (public.has_permission(org_id, 'catalog.write'))
  with check (public.has_permission(org_id, 'catalog.write'));

create policy products_admin_write on public.products for all
  to authenticated
  using (public.has_permission(org_id, 'catalog.write'))
  with check (public.has_permission(org_id, 'catalog.write'));

create policy product_variants_admin_write on public.product_variants for all
  to authenticated
  using (public.has_permission(org_id, 'catalog.write'))
  with check (public.has_permission(org_id, 'catalog.write'));

create policy barcodes_admin_write on public.barcodes for all
  to authenticated
  using (public.has_permission(org_id, 'catalog.write'))
  with check (public.has_permission(org_id, 'catalog.write'));

create policy price_lists_admin_write on public.price_lists for all
  to authenticated
  using (public.has_permission(org_id, 'catalog.write'))
  with check (public.has_permission(org_id, 'catalog.write'));

create policy variant_prices_admin_write on public.variant_prices for all
  to authenticated
  using (public.has_permission(org_id, 'catalog.write'))
  with check (public.has_permission(org_id, 'catalog.write'));

create policy parties_admin_write on public.parties for all
  to authenticated
  using (public.has_permission(org_id, 'catalog.write'))
  with check (public.has_permission(org_id, 'catalog.write'));

create policy replenishment_config_admin_write on public.replenishment_config for all
  to authenticated
  using (public.has_permission(org_id, 'replenishment.write'))
  with check (public.has_permission(org_id, 'replenishment.write'));

alter table public.permissions enable row level security;
alter table public.org_roles enable row level security;
alter table public.org_invitations enable row level security;

create policy permissions_member_read on public.permissions for select
  to authenticated using (true);

revoke all on public.permissions from anon;
revoke all on public.org_roles from anon;
revoke all on public.org_invitations from anon;

grant select on public.permissions to authenticated;
grant select, insert, update, delete on public.org_roles to authenticated;
grant select, insert, update on public.org_invitations to authenticated;
grant execute on function public.has_permission(uuid, text) to authenticated;
grant execute on function public.cresko_accept_invitation(uuid) to authenticated;
grant execute on function public.cresko_org_members(uuid) to authenticated;