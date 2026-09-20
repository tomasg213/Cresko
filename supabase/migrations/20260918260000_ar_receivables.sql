-- Cuentas por cobrar por factura (con el número del documento).

create view public.ar_receivables
with (security_invoker = on) as
select
  a.org_id,
  a.invoice_id,
  i.number as invoice_number,
  a.party_id,
  p.name as party_name,
  a.currency,
  sum(a.amount) as balance
from public.ar_ledger a
join public.invoices i on i.id = a.invoice_id and i.org_id = a.org_id
join public.parties p on p.id = a.party_id and p.org_id = a.org_id
group by a.org_id, a.invoice_id, i.number, a.party_id, p.name, a.currency
having sum(a.amount) <> 0;