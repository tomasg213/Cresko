---
name: cresko-domain
description: Apply Cresko ERP domain invariants for tenant isolation, variants, inventory, documents, pricing, and money. Use for every business feature or schema change.
---

# Cresko Domain

- Resolve `org_id` from the authenticated membership. Never trust a client-provided tenant ID.
- A product is a commercial parent; stock belongs to its variant in a warehouse.
- Retail and wholesale are price lists over the same variants.
- `stock_movements` is the source of truth; a stock projection changes only in the same transaction.
- Posted sales, receipts, invoices, payments, and ledger entries are immutable. Corrections are reversals.
- USD and VES are separate balances. Every monetary document stores currency and exchange rate.
- Checkout must atomically validate stock, write inventory, post the invoice, and write payment/receivable changes.

Before implementation, identify the aggregate, its posting transition, its reversal path, and its tenant boundary.
