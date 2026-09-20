---
name: supabase-rls
description: Design Supabase PostgreSQL migrations, constraints, indexes, and row-level security for Cresko tenant-owned data. Use when changing supabase/migrations.
---

# Supabase RLS

- Every tenant-owned table has non-null `org_id` and RLS enabled.
- Policies must derive access through `auth.uid()` and memberships, not request parameters.
- Add indexes beginning with `org_id` for tenant-scoped access paths.
- Use database constraints for positive quantities, valid currencies, and legal state transitions where practical.
- Keep immutable ledger tables append-only; deny update/delete to normal application roles.
- Avoid service-role access in normal user requests.
- Test both same-tenant access and cross-tenant denial.
