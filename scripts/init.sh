#!/usr/bin/env bash
set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-cresko}"
DB_PASSWORD="${DB_PASSWORD:-cresko}"
DB_NAME="${DB_NAME:-cresko}"

echo "=== Cresko Initialization Script ==="

echo "Creating public schema tables (tenants registry)..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<-SQL
  CREATE TABLE IF NOT EXISTS public.tenants (
      id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      slug        VARCHAR(100) UNIQUE NOT NULL,
      name        VARCHAR(255) NOT NULL,
      schema_name VARCHAR(100) UNIQUE NOT NULL,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
  );
SQL

echo "Initialization complete."
