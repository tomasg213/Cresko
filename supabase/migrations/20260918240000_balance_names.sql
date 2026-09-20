-- Saldos por cobrar/pagar con el nombre del tercero.

drop view if exists public.ar_balances;
drop view if exists public.ap_balances;

create view public.ar_balances
with (security_invoker = on) as
select a.org_id, a.party_id, p.name as party_name, a.currency, sum(a.amount) as balance
from public.ar_ledger a
join public.parties p on p.id = a.party_id and p.org_id = a.org_id
group by a.org_id, a.party_id, p.name, a.currency;

create view public.ap_balances
with (security_invoker = on) as
select a.org_id, a.party_id, p.name as party_name, a.currency, sum(a.amount) as balance
from public.ap_ledger a
join public.parties p on p.id = a.party_id and p.org_id = a.org_id
group by a.org_id, a.party_id, p.name, a.currency;