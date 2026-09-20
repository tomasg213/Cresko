---
name: next-pos
description: Build Cresko Next.js POS workflows with keyboard barcode scanners, camera fallback, catalog cache, and online checkout. Use for POS or barcode UI work.
---

# Next POS

- Treat USB barcode readers as keyboard input and keep the scan field focused.
- Provide camera scanning as a fallback, not as the only workflow.
- Cache catalog data in IndexedDB for lookup speed, but do not confirm sales offline.
- Send checkout to FastAPI; the server is authoritative for price, permission, stock, tax, currency, and totals.
- Make loading, conflict, network failure, and duplicate-submit states explicit.
- Preserve keyboard accessibility for cashier workflows.
