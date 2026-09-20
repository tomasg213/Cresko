# Cresko

ERP SaaS multi-tenant para comercios pequeños y medianos de Venezuela, con ventas al mayor y al detal.

## Estado

Base inicial del proyecto: tenancy, sucursales, almacenes y membresías. Implementados: catálogo (productos, variantes, códigos, precios), inventario (movimientos y proyección), POS con checkout atómico, clientes/proveedores, compras (órdenes y recepción), cuentas por cobrar/pagar, reposición, **roles personalizados con permisos e invitaciones de miembros**, y la interfaz web completa.

## Estructura

```text
apps/web              Next.js
apps/api              FastAPI
packages/api-client   Cliente generado desde OpenAPI
supabase/migrations   Fuente canónica del esquema
.opencode             Agentes, skills y comandos del proyecto
docs                   Decisiones y modelo de dominio
```

## Requisitos

- Node.js 22+
- pnpm 10+
- Python 3.12+
- uv
- Supabase CLI para migraciones remotas

## Inicio rápido

1. Configura las variables de entorno:

```bash
cp .env.example .env.local
cp apps/web/.env.example apps/web/.env.local
```

Completa en ambos archivos la URL del proyecto Supabase y la anon key (Dashboard > Project Settings > API).

2. Instala dependencias y ejecuta:

```bash
pnpm install
uv sync --project apps/api
pnpm dev
```

Variables mínimas: la API lee `supabase_url`, `supabase_anon_key` y `supabase_jwt_secret` (o usa JWKS si se deja vacío). El frontend lee `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` y `NEXT_PUBLIC_API_URL`.

Para aplicar migraciones al proyecto remoto:

```bash
supabase link --project-ref <project-ref>
supabase db push
```

## Decisiones iniciales

- El backend FastAPI es dueño de los casos de uso y transacciones.
- Next.js no modifica inventario directamente.
- El POS es online con catálogo cacheado; no se confirman ventas offline.
- La factura venezolana empieza como documento fiscal configurable, dejando integración SENIAT para una fase posterior.
