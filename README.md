# Cresko ERP

Multi-tenant Enterprise Resource Planning system built with FastAPI, Next.js 14, and PostgreSQL.

**Architecture**: Schema-based multi-tenancy — each tenant gets an isolated PostgreSQL schema (`tenant_{slug}`), while shared data (tenant registry, subscriptions) lives in the `public` schema.

## Tech Stack

| Layer     | Technology                                      |
| --------- | ----------------------------------------------- |
| Backend   | Python 3.10+, FastAPI, SQLAlchemy 2.0 (async), Alembic |
| Frontend  | Node.js 18+, Next.js 14 (App Router), Tailwind CSS, shadcn/ui |
| Database  | PostgreSQL 16                                   |
| Auth      | JWT (PyJWT)                                     |

## Prerequisites

- Python 3.10+
- Node.js 18+
- pnpm
- PostgreSQL 16 (or Docker)

## Quick Start

### 1. Clone and enter the project

```bash
git clone <repo-url> && cd cresko
```

### 2. Start PostgreSQL

```bash
docker compose up -d
```

### 3. Configure environment

```bash
cp .env.example backend/.env
```

### 4. Install dependencies & initialize

```bash
make setup
```

### 5. Run database initialization

```bash
./scripts/init.sh
```

### 6. Start development servers

```bash
make dev
```

- Backend: http://localhost:8000
- Frontend: http://localhost:3000
- Health check: http://localhost:8000/api/v1/health (requires `X-Tenant-ID` header)

## Makefile Commands

| Command         | Description                            |
| --------------- | -------------------------------------- |
| `make setup`    | Install backend + frontend deps        |
| `make dev`      | Run both servers concurrently          |
| `make dev-backend`  | FastAPI with hot reload            |
| `make dev-frontend` | Next.js dev server                |
| `make db-status`    | Test PostgreSQL connectivity      |
| `make db-migrate`   | Run Alembic migrations            |
| `make db-revision message="..."` | Create new migration |
| `make clean`        | Remove virtualenv, node_modules, caches |

## Tenant Isolation

Tenants are identified via the `X-Tenant-ID` HTTP header. The backend dependency `get_db_tenant` executes `SET search_path TO tenant_{id}, public;` on each request, ensuring data isolation at the database level.

The Next.js middleware (`src/middleware.ts`) automatically extracts the subdomain from incoming requests and injects it as the `X-Tenant-ID` header.
