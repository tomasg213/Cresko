-- =====================================================================
-- Limpieza: revierte cargos residuales en VES que quedaron de la
-- conversión a USD (20260918290000_ar_ap_usd). Esos cargos redondeaban a
-- 0.00 USD y no se convirtieron, dejando una "deuda fantasma" impagable
-- porque los pagos CxC/CxP solo se registran en USD.
--
-- La corrección es una reversión (los ledgers son inmutables).
-- =====================================================================

-- CxC: reversar cargos VES sin reversión previa.
insert into public.ar_ledger (
  org_id, party_id, invoice_id, entry_type, amount, currency, created_by
)
select a.org_id, a.party_id, a.invoice_id, 'reversal', -a.amount, 'VES', a.created_by
from public.ar_ledger a
where a.currency = 'VES'
  and a.entry_type = 'charge'
  and not exists (
    select 1 from public.ar_ledger r
    where r.org_id = a.org_id
      and r.invoice_id = a.invoice_id
      and r.entry_type = 'reversal'
      and r.currency = 'VES'
      and r.amount = -a.amount
  );

-- CxP: reversar cargos VES sin reversión previa.
insert into public.ap_ledger (
  org_id, party_id, supplier_invoice_id, entry_type, amount, currency, created_by
)
select a.org_id, a.party_id, a.supplier_invoice_id, 'reversal', -a.amount, 'VES', a.created_by
from public.ap_ledger a
where a.currency = 'VES'
  and a.entry_type = 'charge'
  and not exists (
    select 1 from public.ap_ledger r
    where r.org_id = a.org_id
      and r.supplier_invoice_id = a.supplier_invoice_id
      and r.entry_type = 'reversal'
      and r.currency = 'VES'
      and r.amount = -a.amount
  );