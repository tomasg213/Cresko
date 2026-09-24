-- =====================================================================
-- Finanzas: CxC/CxP por factura y pagos generales (cascada FIFO).
--
-- - Vista ap_receivables (saldo CxP por factura de proveedor).
-- - Pagos generales: un monto se descuenta de la factura más antigua y,
--   si sobra, de la siguiente, sin dejar deuda negativa.
-- - Pagos por factura validan que el monto no supere el saldo pendiente.
-- =====================================================================

create view public.ap_receivables
with (security_invoker = on) as
select
  a.org_id,
  a.supplier_invoice_id,
  si.number as invoice_number,
  a.party_id,
  p.name as party_name,
  a.currency,
  sum(a.amount) as balance
from public.ap_ledger a
join public.supplier_invoices si on si.id = a.supplier_invoice_id and si.org_id = a.org_id
join public.parties p on p.id = a.party_id and p.org_id = a.org_id
group by a.org_id, a.supplier_invoice_id, si.number, a.party_id, p.name, a.currency
having sum(a.amount) <> 0;

grant select on public.ap_receivables to authenticated;

-- =====================================================================
-- Cobro a cliente: valida que el monto no supere el saldo de la factura
-- =====================================================================

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
  v_balance numeric(18, 2);
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
  if p_currency <> 'USD' then
    raise exception 'AR payments must be in USD';
  end if;
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select * into v_invoice from public.invoices
  where org_id = p_org_id and id = p_invoice_id;
  if v_invoice.id is null then
    raise exception 'invoice not found';
  end if;

  select coalesce(sum(amount), 0) into v_balance
  from public.ar_ledger
  where org_id = p_org_id and invoice_id = p_invoice_id and currency = 'USD';
  if v_amount > v_balance then
    raise exception 'El monto no puede ser mayor que la deuda de la factura';
  end if;

  insert into public.payments (
    org_id, invoice_id, amount, currency, exchange_rate, method, created_by
  )
  values (
    p_org_id, v_invoice.id, v_amount, 'USD', v_invoice.exchange_rate, p_method, auth.uid()
  )
  returning * into v_payment;

  insert into public.ar_ledger (
    org_id, party_id, invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_invoice.party_id, v_invoice.id, 'payment', -v_amount, 'USD', auth.uid()
  );

  return v_payment;
end;
$$;

-- =====================================================================
-- Pago a proveedor: valida que el monto no supere el saldo de la factura
-- =====================================================================

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
  v_balance numeric(18, 2);
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
  if p_currency <> 'USD' then
    raise exception 'AP payments must be in USD';
  end if;
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select * into v_invoice from public.supplier_invoices
  where org_id = p_org_id and id = p_supplier_invoice_id;
  if v_invoice.id is null then
    raise exception 'supplier invoice not found';
  end if;

  select coalesce(sum(amount), 0) into v_balance
  from public.ap_ledger
  where org_id = p_org_id and supplier_invoice_id = p_supplier_invoice_id and currency = 'USD';
  if v_amount > v_balance then
    raise exception 'El monto no puede ser mayor que la deuda de la factura';
  end if;

  insert into public.ap_ledger (
    org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by
  )
  values (
    p_org_id, v_invoice.supplier_id, v_invoice.id, 'payment', -v_amount, 'USD', auth.uid()
  )
  returning * into v_ledger;

  return v_ledger;
end;
$$;

-- =====================================================================
-- Pago general de clientes (CxC): descuenta de la factura más antigua
-- y si sobra, de la siguiente. Rechaza montos mayores a toda la deuda.
-- =====================================================================

create or replace function public.cresko_apply_ar_payment(
  p_org_id uuid,
  p_party_id uuid,
  p_amount numeric,
  p_currency text,
  p_method text default 'cash'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(18, 2) := round(p_amount, 2);
  v_total numeric(18, 2);
  v_remaining numeric(18, 2);
  v_row record;
  v_applied numeric(18, 2);
  v_inv public.invoices;
  v_result jsonb := '[]'::jsonb;
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
  if p_currency <> 'USD' then
    raise exception 'AR payments must be in USD';
  end if;
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select coalesce(sum(balance), 0) into v_total
  from (
    select sum(amount) as balance
    from public.ar_ledger
    where org_id = p_org_id and party_id = p_party_id and currency = p_currency
    group by invoice_id
    having sum(amount) > 0
  ) b;

  if v_amount > v_total then
    raise exception 'El monto no puede ser mayor que toda la deuda';
  end if;

  v_remaining := v_amount;
  for v_row in
    select a.invoice_id, sum(a.amount) as balance, min(i.created_at) as created_at
    from public.ar_ledger a
    join public.invoices i on i.id = a.invoice_id and i.org_id = a.org_id
    where a.org_id = p_org_id and a.party_id = p_party_id and a.currency = p_currency
    group by a.invoice_id
    having sum(a.amount) > 0
    order by min(i.created_at) asc, a.invoice_id asc
  loop
    exit when v_remaining <= 0;
    v_applied := least(v_remaining, v_row.balance);
    if v_applied > 0 then
      select * into v_inv from public.invoices where id = v_row.invoice_id;
      insert into public.payments (
        org_id, invoice_id, amount, currency, exchange_rate, method, created_by
      )
      values (
        p_org_id, v_row.invoice_id, v_applied, 'USD', v_inv.exchange_rate, p_method, auth.uid()
      );
      insert into public.ar_ledger (
        org_id, party_id, invoice_id, entry_type, amount, currency, created_by
      )
      values (
        p_org_id, p_party_id, v_row.invoice_id, 'payment', -v_applied, 'USD', auth.uid()
      );
      v_result := v_result || jsonb_build_object('invoice_id', v_row.invoice_id, 'amount', v_applied);
      v_remaining := round(v_remaining - v_applied, 2);
    end if;
  end loop;

  return v_result;
end;
$$;

grant execute on function public.cresko_apply_ar_payment(uuid, uuid, numeric, text, text) to authenticated;

-- =====================================================================
-- Pago general de proveedores (CxP): descuenta de la factura más antigua
-- y si sobra, de la siguiente. Rechaza montos mayores a toda la deuda.
-- =====================================================================

create or replace function public.cresko_apply_ap_payment(
  p_org_id uuid,
  p_party_id uuid,
  p_amount numeric,
  p_currency text,
  p_method text default 'cash'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(18, 2) := round(p_amount, 2);
  v_total numeric(18, 2);
  v_remaining numeric(18, 2);
  v_row record;
  v_applied numeric(18, 2);
  v_result jsonb := '[]'::jsonb;
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
  if p_currency <> 'USD' then
    raise exception 'AP payments must be in USD';
  end if;
  if p_method not in ('cash', 'card', 'transfer') then
    raise exception 'unsupported payment method';
  end if;

  select coalesce(sum(balance), 0) into v_total
  from (
    select sum(amount) as balance
    from public.ap_ledger
    where org_id = p_org_id and party_id = p_party_id and currency = p_currency
    group by supplier_invoice_id
    having sum(amount) > 0
  ) b;

  if v_amount > v_total then
    raise exception 'El monto no puede ser mayor que toda la deuda';
  end if;

  v_remaining := v_amount;
  for v_row in
    select a.supplier_invoice_id, sum(a.amount) as balance, min(si.created_at) as created_at
    from public.ap_ledger a
    join public.supplier_invoices si on si.id = a.supplier_invoice_id and si.org_id = a.org_id
    where a.org_id = p_org_id and a.party_id = p_party_id and a.currency = p_currency
    group by a.supplier_invoice_id
    having sum(a.amount) > 0
    order by min(si.created_at) asc, a.supplier_invoice_id asc
  loop
    exit when v_remaining <= 0;
    v_applied := least(v_remaining, v_row.balance);
    if v_applied > 0 then
      insert into public.ap_ledger (
        org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by
      )
      values (
        p_org_id, p_party_id, v_row.supplier_invoice_id, 'payment', -v_applied, 'USD', auth.uid()
      );
      v_result := v_result || jsonb_build_object('invoice_id', v_row.supplier_invoice_id, 'amount', v_applied);
      v_remaining := round(v_remaining - v_applied, 2);
    end if;
  end loop;

  return v_result;
end;
$$;

grant execute on function public.cresko_apply_ap_payment(uuid, uuid, numeric, text, text) to authenticated;