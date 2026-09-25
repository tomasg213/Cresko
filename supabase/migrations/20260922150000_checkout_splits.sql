-- =====================================================================
-- Checkout con pago fraccionado (efectivo/tarjeta/biopago) y validación
-- de cuadre de caja abierto. El total pagado se reparte entre métodos;
-- el saldo restante queda como crédito (fiado).
-- =====================================================================

create or replace function public.cresko_checkout(
  p_org_id uuid,
  p_warehouse_id uuid,
  p_price_list_code text,
  p_exchange_rate numeric,
  p_tax_rate numeric,
  p_lines jsonb,
  p_payment_method text default 'cash',
  p_paid_amount numeric default 0,
  p_party_id uuid default null,
  p_party jsonb default null,
  p_payments jsonb default null
) returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_close public.cash_closes;
  v_list_id uuid;
  v_number bigint;
  v_invoice public.invoices;
  v_line jsonb;
  v_price_usd numeric(18, 2);
  v_unit_price_ves numeric(18, 2);
  v_qty numeric(18, 3);
  v_line_usd numeric(18, 2);
  v_line_ves numeric(18, 2);
  v_line_tax_usd numeric(18, 2);
  v_line_tax_ves numeric(18, 2);
  v_taxable boolean;
  v_subtotal_usd numeric(18, 2) := 0;
  v_tax_usd numeric(18, 2) := 0;
  v_total_usd numeric(18, 2);
  v_subtotal_ves numeric(18, 2) := 0;
  v_tax_ves numeric(18, 2) := 0;
  v_total_ves numeric(18, 2);
  v_paid_usd numeric(18, 2);
  v_balance_usd numeric(18, 2);
  v_level public.stock_levels;
  v_party_id uuid;
  v_invoice_id uuid;
  v_pay jsonb;
  v_pay_method text;
  v_pay_amount numeric(18, 2);
  v_pay_sum numeric(18, 2) := 0;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'organization access denied';
  end if;
  if not public.has_permission(p_org_id, 'sales.checkout') then
    raise exception 'insufficient permissions';
  end if;

  -- Cuadre de caja: debe existir un cuadre abierto del día.
  v_close := public.cresko_ensure_open_close(p_org_id);

  if p_exchange_rate is null or p_exchange_rate <= 0 then
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

    select amount into v_price_usd
    from public.variant_prices
    where org_id = p_org_id
      and variant_id = (v_line ->> 'variant_id')::uuid
      and price_list_id = v_list_id
      and currency = 'USD';
    if v_price_usd is null then
      raise exception 'no USD price for variant % in list %', v_line ->> 'variant_id', p_price_list_code;
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

    select coalesce(p.is_taxable, true) into v_taxable
    from public.product_variants v
    join public.products p on p.id = v.product_id and p.org_id = v.org_id
    where v.id = (v_line ->> 'variant_id')::uuid and v.org_id = p_org_id;

    v_line_usd := round(v_price_usd * v_qty, 2);
    v_line_ves := round(v_line_usd * p_exchange_rate, 2);
    if v_taxable then
      v_line_tax_usd := round(v_line_usd * p_tax_rate / 100, 2);
    else
      v_line_tax_usd := 0;
    end if;
    v_line_tax_ves := round(v_line_tax_usd * p_exchange_rate, 2);

    v_subtotal_usd := v_subtotal_usd + v_line_usd;
    v_tax_usd := v_tax_usd + v_line_tax_usd;
    v_subtotal_ves := v_subtotal_ves + v_line_ves;
    v_tax_ves := v_tax_ves + v_line_tax_ves;
  end loop;

  v_total_usd := round(v_subtotal_usd + v_tax_usd, 2);
  v_total_ves := round(v_subtotal_ves + v_tax_ves, 2);

  -- Pago fraccionado: si viene p_payments, la suma define lo pagado.
  if p_payments is not null and jsonb_typeof(p_payments) = 'array' then
    v_pay_sum := 0;
    for v_pay in select value from jsonb_array_elements(p_payments)
    loop
      v_pay_amount := round(coalesce((v_pay ->> 'amount')::numeric, 0), 2);
      if v_pay_amount < 0 then
        raise exception 'payment amount must not be negative';
      end if;
      v_pay_sum := round(v_pay_sum + v_pay_amount, 2);
    end loop;
    v_paid_usd := least(v_pay_sum, v_total_usd);
  else
    v_paid_usd := least(round(coalesce(p_paid_amount, 0), 2), v_total_usd);
  end if;

  v_balance_usd := greatest(round(v_total_usd - v_paid_usd, 2), 0);

  if v_balance_usd > 0 and v_party_id is null then
    raise exception 'credit sale requires a party';
  end if;
  if v_balance_usd > 0 and not public.has_permission(p_org_id, 'sales.credit') then
    raise exception 'insufficient permissions for credit sale';
  end if;

  insert into public.invoices (
    org_id, number, party_id, subtotal, tax, total,
    currency, exchange_rate, tax_rate, status, created_by
  )
  values (
    p_org_id, format('FAC-%s', lpad(v_number::text, 8, '0')), v_party_id,
    v_subtotal_ves, v_tax_ves, v_total_ves, 'VES', p_exchange_rate, p_tax_rate, 'posted', auth.uid()
  )
  returning * into v_invoice;
  v_invoice_id := v_invoice.id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_qty := (v_line ->> 'qty')::numeric;
    select amount into v_price_usd
    from public.variant_prices
    where org_id = p_org_id
      and variant_id = (v_line ->> 'variant_id')::uuid
      and price_list_id = v_list_id
      and currency = 'USD';

    select coalesce(p.is_taxable, true) into v_taxable
    from public.product_variants v
    join public.products p on p.id = v.product_id and p.org_id = v.org_id
    where v.id = (v_line ->> 'variant_id')::uuid and v.org_id = p_org_id;

    v_unit_price_ves := round(v_price_usd * p_exchange_rate, 2);
    v_line_usd := round(v_price_usd * v_qty, 2);
    v_line_ves := round(v_line_usd * p_exchange_rate, 2);
    if v_taxable then
      v_line_tax_usd := round(v_line_usd * p_tax_rate / 100, 2);
    else
      v_line_tax_usd := 0;
    end if;
    v_line_tax_ves := round(v_line_tax_usd * p_exchange_rate, 2);

    insert into public.invoice_lines (
      org_id, invoice_id, variant_id, qty, unit_price, line_total, tax, currency
    )
    values (
      p_org_id, v_invoice_id, (v_line ->> 'variant_id')::uuid,
      v_qty, v_unit_price_ves, v_line_ves, v_line_tax_ves, 'VES'
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

  -- Registrar pagos por método (split) o un único pago.
  if v_paid_usd > 0 then
    if p_payments is not null and jsonb_typeof(p_payments) = 'array' then
      for v_pay in select value from jsonb_array_elements(p_payments)
      loop
        v_pay_method := v_pay ->> 'method';
        if v_pay_method not in ('cash', 'card', 'biopago', 'transfer') then
          raise exception 'unsupported payment method: %', v_pay_method;
        end if;
        v_pay_amount := round(coalesce((v_pay ->> 'amount')::numeric, 0), 2);
        if v_pay_amount > 0 then
          insert into public.payments (
            org_id, invoice_id, amount, currency, exchange_rate, method, created_by
          )
          values (
            p_org_id, v_invoice_id, least(v_pay_amount, v_total_usd - coalesce((select sum(amount) from public.payments where org_id = p_org_id and invoice_id = v_invoice_id), 0)),
            'USD', p_exchange_rate, v_pay_method, auth.uid()
          );
        end if;
      end loop;
    else
      if p_payment_method not in ('cash', 'card', 'biopago', 'transfer', 'credit') then
        raise exception 'unsupported payment method';
      end if;
      insert into public.payments (
        org_id, invoice_id, amount, currency, exchange_rate, method, created_by
      )
      values (
        p_org_id, v_invoice_id, v_paid_usd, 'USD', p_exchange_rate,
        p_payment_method, auth.uid()
      );
    end if;
  end if;

  if v_balance_usd > 0 then
    insert into public.ar_ledger (
      org_id, party_id, invoice_id, entry_type, amount, currency, created_by
    )
    values (
      p_org_id, v_party_id, v_invoice_id, 'charge', v_balance_usd, 'USD', auth.uid()
    );
  end if;

  return v_invoice;
end;
$$;

grant execute on function public.cresko_checkout(
  uuid, uuid, text, numeric, numeric, jsonb, text, numeric, uuid, jsonb, jsonb
) to authenticated;