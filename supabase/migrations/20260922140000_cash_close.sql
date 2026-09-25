-- =====================================================================
-- Cuadre de caja.
--
-- Cada cuadre dura un día: al primer movimiento del día se asegura un
-- cuadre abierto; si el cuadre abierto es de un día anterior (no se
-- cerró), no se puede vender hasta cerrarlo.
--
-- El cuadre captura facturas y pedidos con su desglose de pagos:
-- efectivo, tarjeta, biopago y crédito (fiado).
--
-- También se agrega el método de pago "biopago".
-- =====================================================================

-- =====================================================================
-- Métodos de pago: agregar biopago
-- =====================================================================

alter table public.payments
  drop constraint if exists payments_method_check;
alter table public.payments
  add constraint payments_method_check
  check (method in ('cash', 'card', 'transfer', 'credit', 'biopago'));

alter table public.order_payments
  drop constraint if exists order_payments_method_check;
alter table public.order_payments
  add constraint order_payments_method_check
  check (method in ('cash', 'card', 'transfer', 'biopago'));

-- =====================================================================
-- Cuadres de caja
-- =====================================================================

create table public.cash_closes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  number text not null,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  status text not null default 'open' check (status in ('open', 'closed')),
  opened_by uuid not null references auth.users(id),
  closed_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, number),
  unique (id, org_id)
);

create index cash_closes_org_idx on public.cash_closes (org_id, created_at desc);
create trigger cash_closes_set_updated_at before update on public.cash_closes
  for each row execute function public.set_updated_at();

-- =====================================================================
-- Transacciones del cuadre (snapshot inmutable)
-- =====================================================================

create table public.cash_close_transactions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  cash_close_id uuid not null,
  source text not null check (source in ('invoice', 'order')),
  source_id uuid not null,
  number text not null,
  party_name text,
  total_usd numeric(18, 2) not null check (total_usd >= 0),
  paid_usd numeric(18, 2) not null default 0 check (paid_usd >= 0),
  balance_usd numeric(18, 2) not null default 0 check (balance_usd >= 0),
  cash_usd numeric(18, 2) not null default 0 check (cash_usd >= 0),
  card_usd numeric(18, 2) not null default 0 check (card_usd >= 0),
  biopago_usd numeric(18, 2) not null default 0 check (biopago_usd >= 0),
  credit_usd numeric(18, 2) not null default 0 check (credit_usd >= 0),
  created_at timestamptz not null default now(),
  unique (id, org_id),
  unique (org_id, source, source_id),
  constraint cash_close_transactions_close_same_org foreign key (cash_close_id, org_id)
    references public.cash_closes (id, org_id)
);

create index cash_close_transactions_org_idx
  on public.cash_close_transactions (org_id, cash_close_id);

-- =====================================================================
-- Asegurar cuadre abierto del día. Bloquea si el cuadre abierto es de
-- un día anterior (no se cerró).
-- =====================================================================

create or replace function public.cresko_ensure_open_close(p_org_id uuid)
returns public.cash_closes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_close public.cash_closes;
  v_number bigint;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;

  select * into v_close
  from public.cash_closes
  where org_id = p_org_id
  order by created_at desc
  limit 1;

  if v_close.id is not null and v_close.status = 'open' then
    if v_close.opened_at::date < current_date then
      raise exception 'Debes realizar el cuadre de caja del día anterior antes de vender';
    end if;
    return v_close;
  end if;

  insert into public.document_sequences (org_id, kind, last_number)
  values (p_org_id, 'cc', 1)
  on conflict (org_id, kind)
  do update set last_number = public.document_sequences.last_number + 1
  returning last_number into v_number;

  insert into public.cash_closes (org_id, number, opened_at, status, opened_by)
  values (
    p_org_id, format('CC-%s', lpad(v_number::text, 8, '0')),
    now(), 'open', auth.uid()
  )
  returning * into v_close;

  return v_close;
end;
$$;

-- =====================================================================
-- Cerrar cuadre: captura facturas y pedidos del rango y los guarda como
-- snapshot. Retorna el resumen por método de pago.
-- =====================================================================

create or replace function public.cresko_close_cash_register(
  p_org_id uuid,
  p_cash_close_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_close public.cash_closes;
  v_total numeric(18, 2) := 0;
  v_paid numeric(18, 2) := 0;
  v_balance numeric(18, 2) := 0;
  v_cash numeric(18, 2) := 0;
  v_card numeric(18, 2) := 0;
  v_biopago numeric(18, 2) := 0;
  v_credit numeric(18, 2) := 0;
  v_tx_count int := 0;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'finance.receive') then
    raise exception 'insufficient permissions';
  end if;

  select * into v_close from public.cash_closes
  where org_id = p_org_id and id = p_cash_close_id;
  if v_close.id is null then
    raise exception 'cash close not found';
  end if;
  if v_close.status <> 'open' then
    raise exception 'cash close is already closed';
  end if;

  -- Facturas del cuadre (rango opened_at..now)
  insert into public.cash_close_transactions (
    org_id, cash_close_id, source, source_id, number, party_name,
    total_usd, paid_usd, balance_usd, cash_usd, card_usd, biopago_usd, credit_usd
  )
  select
    p_org_id, p_cash_close_id, 'invoice', i.id, i.number, p.name,
    round(i.total / i.exchange_rate, 2),
    coalesce(pay.paid, 0),
    greatest(round(i.total / i.exchange_rate, 2) - coalesce(pay.paid, 0), 0),
    coalesce(pay.cash, 0),
    coalesce(pay.card, 0),
    coalesce(pay.biopago, 0),
    greatest(round(i.total / i.exchange_rate, 2) - coalesce(pay.paid, 0), 0)
  from public.invoices i
  left join public.parties p on p.id = i.party_id and p.org_id = i.org_id
  left join (
    select invoice_id,
      sum(amount) filter (where method = 'cash') as cash,
      sum(amount) filter (where method = 'card') as card,
      sum(amount) filter (where method = 'biopago') as biopago,
      sum(amount) as paid
    from public.payments
    where org_id = p_org_id
    group by invoice_id
  ) pay on pay.invoice_id = i.id
  where i.org_id = p_org_id
    and i.created_at >= v_close.opened_at
    and i.created_at <= coalesce(v_close.closed_at, now())
    and not exists (
      select 1 from public.cash_close_transactions t
      where t.org_id = p_org_id and t.source = 'invoice' and t.source_id = i.id
    );

  -- Pedidos del cuadre
  insert into public.cash_close_transactions (
    org_id, cash_close_id, source, source_id, number, party_name,
    total_usd, paid_usd, balance_usd, cash_usd, card_usd, biopago_usd, credit_usd
  )
  select
    p_org_id, p_cash_close_id, 'order', o.id, o.number, p.name,
    round(o.total / o.exchange_rate, 2),
    coalesce(pay.paid, 0),
    greatest(round(o.total / o.exchange_rate, 2) - coalesce(pay.paid, 0), 0),
    coalesce(pay.cash, 0),
    coalesce(pay.card, 0),
    coalesce(pay.biopago, 0),
    greatest(round(o.total / o.exchange_rate, 2) - coalesce(pay.paid, 0), 0)
  from public.orders o
  left join public.parties p on p.id = o.party_id and p.org_id = o.org_id
  left join (
    select order_id,
      sum(amount) filter (where method = 'cash') as cash,
      sum(amount) filter (where method = 'card') as card,
      sum(amount) filter (where method = 'biopago') as biopago,
      sum(amount) as paid
    from public.order_payments
    where org_id = p_org_id
    group by order_id
  ) pay on pay.order_id = o.id
  where o.org_id = p_org_id
    and o.created_at >= v_close.opened_at
    and o.created_at <= coalesce(v_close.closed_at, now())
    and not exists (
      select 1 from public.cash_close_transactions t
      where t.org_id = p_org_id and t.source = 'order' and t.source_id = o.id
    );

  -- Resumen
  select
    coalesce(sum(total_usd), 0),
    coalesce(sum(paid_usd), 0),
    coalesce(sum(balance_usd), 0),
    coalesce(sum(cash_usd), 0),
    coalesce(sum(card_usd), 0),
    coalesce(sum(biopago_usd), 0),
    coalesce(sum(credit_usd), 0),
    count(*)
  into v_total, v_paid, v_balance, v_cash, v_card, v_biopago, v_credit, v_tx_count
  from public.cash_close_transactions
  where org_id = p_org_id and cash_close_id = p_cash_close_id;

  update public.cash_closes
  set status = 'closed', closed_at = now(), closed_by = auth.uid()
  where id = p_cash_close_id;

  return jsonb_build_object(
    'cash_close_id', p_cash_close_id,
    'number', v_close.number,
    'opened_at', v_close.opened_at,
    'closed_at', now(),
    'transactions', v_tx_count,
    'total_usd', v_total,
    'paid_usd', v_paid,
    'balance_usd', v_balance,
    'cash_usd', v_cash,
    'card_usd', v_card,
    'biopago_usd', v_biopago,
    'credit_usd', v_credit
  );
end;
$$;

-- =====================================================================
-- RLS
-- =====================================================================

alter table public.cash_closes enable row level security;
alter table public.cash_close_transactions enable row level security;

create policy cash_closes_member_read on public.cash_closes for select
  to authenticated using (public.is_org_member(org_id));
create policy cash_closes_member_write on public.cash_closes for insert
  to authenticated with check (public.is_org_member(org_id));
create policy cash_closes_admin_update on public.cash_closes for update
  to authenticated
  using (public.has_permission(org_id, 'finance.receive'))
  with check (public.has_permission(org_id, 'finance.receive'));

create policy cash_close_transactions_member_read on public.cash_close_transactions for select
  to authenticated using (public.is_org_member(org_id));
create policy cash_close_transactions_member_write on public.cash_close_transactions for insert
  to authenticated with check (public.is_org_member(org_id));

revoke all on public.cash_closes from anon;
revoke all on public.cash_close_transactions from anon;

grant select, insert, update on public.cash_closes to authenticated;
grant select, insert on public.cash_close_transactions to authenticated;

grant execute on function public.cresko_ensure_open_close(uuid) to authenticated;
grant execute on function public.cresko_close_cash_register(uuid, uuid) to authenticated;

-- =====================================================================
-- Números CC en document_sequences
-- =====================================================================

alter table public.document_sequences
  drop constraint if exists document_sequences_kind_check;
alter table public.document_sequences
  add constraint document_sequences_kind_check
  check (kind in ('po', 'gr', 'purchase', 'order', 'cc'));