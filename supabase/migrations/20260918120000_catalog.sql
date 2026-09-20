create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  parent_id uuid references public.categories(id) on delete restrict,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, org_id),
  constraint categories_parent_same_org foreign key (parent_id, org_id)
    references public.categories (id, org_id)
);

create index categories_org_idx on public.categories (org_id, is_active);

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, name),
  unique (id, org_id)
);

create index brands_org_idx on public.brands (org_id, is_active);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  brand_id uuid references public.brands(id) on delete set null,
  name text not null check (length(trim(name)) between 1 and 180),
  description text,
  base_unit text not null default 'unit'
    check (base_unit in ('unit', 'kg', 'g', 'l', 'ml', 'box', 'pair', 'pack')),
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, org_id),
  constraint products_category_same_org foreign key (category_id, org_id)
    references public.categories (id, org_id),
  constraint products_brand_same_org foreign key (brand_id, org_id)
    references public.brands (id, org_id)
);

create index products_org_idx on public.products (org_id, is_active);
create index products_name_idx on public.products (org_id, lower(name));

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null,
  sku text not null,
  name text not null,
  attributes jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, sku),
  unique (id, org_id),
  constraint variants_product_same_org foreign key (product_id, org_id)
    references public.products (id, org_id)
);

create index product_variants_org_idx on public.product_variants (org_id, product_id, is_active);

create table public.barcodes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  variant_id uuid not null,
  barcode text not null,
  format text not null default 'EAN13'
    check (format in ('EAN13', 'EAN8', 'UPC_A', 'UPC_E', 'CODE128', 'CODE39', 'INTERNAL')),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  unique (org_id, barcode),
  unique (id, org_id),
  constraint barcodes_variant_same_org foreign key (variant_id, org_id)
    references public.product_variants (id, org_id)
);

create index barcodes_org_idx on public.barcodes (org_id, variant_id);
create index barcodes_lookup_idx on public.barcodes (org_id, barcode);

create table public.price_lists (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text not null check (code in ('retail', 'wholesale')),
  name text not null check (length(trim(name)) between 1 and 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, code),
  unique (id, org_id)
);

create index price_lists_org_idx on public.price_lists (org_id, is_active);

create table public.variant_prices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  variant_id uuid not null,
  price_list_id uuid not null,
  currency text not null check (currency in ('VES', 'USD')),
  amount numeric(18, 2) not null check (amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, variant_id, price_list_id, currency),
  unique (id, org_id),
  constraint variant_prices_variant_same_org foreign key (variant_id, org_id)
    references public.product_variants (id, org_id),
  constraint variant_prices_list_same_org foreign key (price_list_id, org_id)
    references public.price_lists (id, org_id)
);

create index variant_prices_org_idx on public.variant_prices (org_id, variant_id);

create trigger categories_set_updated_at before update on public.categories
  for each row execute function public.set_updated_at();
create trigger brands_set_updated_at before update on public.brands
  for each row execute function public.set_updated_at();
create trigger products_set_updated_at before update on public.products
  for each row execute function public.set_updated_at();
create trigger product_variants_set_updated_at before update on public.product_variants
  for each row execute function public.set_updated_at();
create trigger price_lists_set_updated_at before update on public.price_lists
  for each row execute function public.set_updated_at();
create trigger variant_prices_set_updated_at before update on public.variant_prices
  for each row execute function public.set_updated_at();

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
  if not public.is_org_admin(p_org_id) then
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

alter table public.categories enable row level security;
alter table public.brands enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.barcodes enable row level security;
alter table public.price_lists enable row level security;
alter table public.variant_prices enable row level security;

create policy categories_member_read on public.categories for select
  to authenticated using (public.is_org_member(org_id));
create policy categories_admin_write on public.categories for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

create policy brands_member_read on public.brands for select
  to authenticated using (public.is_org_member(org_id));
create policy brands_admin_write on public.brands for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

create policy products_member_read on public.products for select
  to authenticated using (public.is_org_member(org_id));
create policy products_admin_write on public.products for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

create policy product_variants_member_read on public.product_variants for select
  to authenticated using (public.is_org_member(org_id));
create policy product_variants_admin_write on public.product_variants for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

create policy barcodes_member_read on public.barcodes for select
  to authenticated using (public.is_org_member(org_id));
create policy barcodes_admin_write on public.barcodes for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

create policy price_lists_member_read on public.price_lists for select
  to authenticated using (public.is_org_member(org_id));
create policy price_lists_admin_write on public.price_lists for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

create policy variant_prices_member_read on public.variant_prices for select
  to authenticated using (public.is_org_member(org_id));
create policy variant_prices_admin_write on public.variant_prices for all
  to authenticated
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

revoke all on public.categories from anon;
revoke all on public.brands from anon;
revoke all on public.products from anon;
revoke all on public.product_variants from anon;
revoke all on public.barcodes from anon;
revoke all on public.price_lists from anon;
revoke all on public.variant_prices from anon;

grant select, insert, update, delete on public.categories to authenticated;
grant select, insert, update, delete on public.brands to authenticated;
grant select, insert, update, delete on public.products to authenticated;
grant select, insert, update, delete on public.product_variants to authenticated;
grant select, insert, update, delete on public.barcodes to authenticated;
grant select, insert, update, delete on public.price_lists to authenticated;
grant select, insert, update, delete on public.variant_prices to authenticated;
grant execute on function public.set_updated_at() to authenticated;
grant execute on function public.cresko_create_product(
  uuid, text, jsonb, uuid, uuid, text, text
) to authenticated;