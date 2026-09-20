---
name: venezuela-money
description: Implement Venezuelan monetary, tax, exchange-rate, invoice, and accounts-receivable/payable behavior without mixing USD and VES. Use for financial features.
---

# Venezuela Money

- Store amounts as integer minor units or exact numeric values, never binary floating point.
- Store currency on every document and monetary line. USD and VES balances are independent.
- Store the exchange rate and its source/time on each monetary document; never silently use today’s rate for an old document.
- Make IVA configurable per organization and product; do not hard-code tax behavior into the UI.
- Treat posted documents and ledger entries as immutable; use reversals for corrections.
- Keep SENIAT integration behind an adapter so internal documents can ship first.
