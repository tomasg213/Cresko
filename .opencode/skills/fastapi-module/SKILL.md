---
name: fastapi-module
description: Implement Cresko FastAPI routers, Pydantic schemas, services, authorization, and transactional tests. Use when changing apps/api.
---

# FastAPI Module

- Keep routers thin; put business rules in services.
- Validate quantities, amounts, currency, and state transitions server-side.
- Resolve the authenticated membership before loading tenant data.
- Use one database transaction for a complete business operation.
- Never implement inventory changes without a movement and locked projection update.
- Add tests for authorization, tenant isolation, invalid money, and rollback on failure.
