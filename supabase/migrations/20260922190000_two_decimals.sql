-- =====================================================================
-- Cantidades y montos con exactamente 2 decimales en todo el sistema.
-- =====================================================================

alter table public.stock_levels alter column qty type numeric(18, 2);
alter table public.stock_movements alter column qty type numeric(18, 2);
alter table public.stock_movements alter column balance_after type numeric(18, 2);
alter table public.invoice_lines alter column qty type numeric(18, 2);
alter table public.po_lines alter column qty_ordered type numeric(18, 2);
alter table public.po_lines alter column qty_received type numeric(18, 2);
alter table public.receipt_lines alter column qty type numeric(18, 2);
alter table public.replenishment_config alter column min_qty type numeric(18, 2);
alter table public.replenishment_config alter column max_qty type numeric(18, 2);
alter table public.replenishment_config alter column pack_multiple type numeric(18, 2);
alter table public.orders alter column qty type numeric(18, 2);