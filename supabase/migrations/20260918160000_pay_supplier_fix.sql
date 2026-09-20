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
  v_role public.member_role;
  v_invoice public.supplier_invoices;
  v_ledger public.ap_ledger;
  v_amount numeric(18, 2) := round(p_amount, 2);
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;

  select role into v_role from public.memberships
  where org_id = p_org_id and user_id = auth.uid();
  if v_role is null or v_role not in ('owner', 'admin', 'purchasing') then
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

revoke execute on function public.cresko_pay_supplier(uuid, uuid, numeric, text, text) from authenticated;
grant execute on function public.cresko_pay_supplier(uuid, uuid, numeric, text, text) to authenticated;