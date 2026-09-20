# Cresko Engineering Rules

## Product

Cresko is a multi-tenant ERP for Venezuelan small and medium commerce, supporting retail and wholesale sales.

## Non-negotiable domain rules

- Every tenant-owned table has `org_id` and is protected by RLS.
- The client cannot choose its tenant. Resolve `org_id` from the authenticated membership.
- Stock is held by a product variant in a warehouse, never by the parent product.
- `stock_movements` is the source of truth. A stock projection may be updated only in the same database transaction as its movement.
- Sales, receipts, invoices, payments, and ledger entries are immutable after posting. Corrections use reversals.
- USD and VES amounts are never combined. Every monetary document stores currency and exchange rate.
- Wholesale and retail pricing are price lists, not duplicated products.
- A checkout either completes all inventory, invoice, payment, and receivable changes or completes none.

## Stack

- `apps/web`: Next.js App Router, TypeScript, Tailwind, TanStack Query.
- `apps/api`: FastAPI, Pydantic v2, SQLAlchemy 2, pytest.
- `supabase`: PostgreSQL migrations, Auth, Storage, and RLS.
- Use pnpm for JavaScript and uv for Python.

## Change workflow

1. Read the relevant skill before changing a module.
2. Define or update the migration before implementing API behavior.
3. Keep domain rules in FastAPI services or PostgreSQL transactions, not UI code.
4. Add tests for tenant isolation, permissions, currency, and transactional failure paths.
5. Run format, lint, typecheck, and tests for the affected app.

## Security

- Never log tokens, secrets, full payment details, or personal data unnecessarily.
- Never use the Supabase service role for a normal user request.
- Validate all monetary values and quantities server-side.
- Prefer deny-by-default permissions and explicit role checks.
