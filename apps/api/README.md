# Cresko API

## Desarrollo

Desde la raíz del repositorio:

```bash
uv sync --project apps/api
uv run --project apps/api uvicorn --app-dir apps/api/src cresko_api.main:app --reload
```

## Autenticación y tenancy

- Los endpoints protegidos requieren `Authorization: Bearer <supabase-access-token>`.
- El token se valida con `SUPABASE_JWT_SECRET` en desarrollo o con el JWKS de Supabase cuando no hay secreto configurado.
- `GET /v1/me` devuelve el usuario y sus membresías.
- `GET /v1/context` resuelve la organización actual. Si el usuario tiene varias membresías, requiere `X-Org-ID`.
- `X-Org-ID` solo selecciona una membresía ya existente; no concede acceso por sí mismo.
- Las consultas de datos deben continuar usando el JWT del usuario para que RLS se aplique.

La API nunca debe aceptar `org_id` como autoridad proveniente del cliente.
