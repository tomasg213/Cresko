# Modelo de dominio inicial

## Tenancy

Una organización representa un comercio. Sus sucursales agrupan almacenes y sus membresías conectan usuarios de Supabase Auth con roles. Ninguna consulta de usuario debe aceptar `org_id` como fuente de autoridad.

## Catálogo

Implementado: `products`, `product_variants`, `barcodes`, `price_lists` (`retail`/`wholesale`) y `variant_prices`. El stock vive en la variante, nunca en el producto padre. Cada variante admite varios códigos de barras y precios por lista y moneda. La creación de producto con variantes es transaccional vía `cresko_create_product`.

## Inventario

Implementado: `stock_movements` como fuente de verdad y `stock_levels` como proyección. La proyección solo cambia dentro de la misma transacción que crea el movimiento (`cresko_adjust_stock` bloquea la fila con `SELECT ... FOR UPDATE` y rechaza saldos negativos). Los clientes no pueden escribir `stock_levels` ni `stock_movements` directamente: solo leen vía REST, y toda mutación pasa por funciones de dominio con verificación de rol (`owner`/`admin`/`warehouse`).

## Ventas (POS)

Implementado: `parties`, `invoices`, `invoice_lines`, `payments` y `ar_ledger`. El checkout (`cresko_checkout`) es atómico: valida stock, descuenta inventario con su movimiento, toma el precio de la lista del servidor, calcula IVA, emite factura numerada por organización y registra pago o cuenta por cobrar (fiado) en la misma transacción. Facturas, líneas, pagos y ledgers son inmutables después del posteo. La moneda y la tasa de cambio se guardan en cada documento; los saldos USD y VES nunca se combinan.

## Compras y cuentas por pagar

Implementado: `purchase_orders`, `po_lines`, `goods_receipts`, `receipt_lines`, `supplier_invoices` y `ap_ledger`. La creación de órdenes es transaccional (`cresko_create_purchase_order`) y la recepción de mercancía (`cresko_receive_goods`) aplica entradas de stock con su movimiento, actualiza la orden, emite la factura del proveedor y registra el cargo en CxP, todo en una transacción. Los pagos a proveedores derivan el tercero de la factura y se registran en `ap_ledger`.

## Reposición

`replenishment_config` define niveles mín/máx, múltiplo de empaque, proveedor preferido y tiempo de reposición por variante y almacén. `cresko_replenishment_needed` calcula qué pedir: `on_hand + on_order < min` sugiere la cantidad hasta `max` redondeada al múltiplo.

## Frontend

Interfaz Next.js con autenticación Supabase, selector de comercio, catálogo, inventario, POS (lector de códigos keyboard-first, caché de catálogo en IndexedDB, checkout online), clientes/proveedores, compras, finanzas y reposición.

## Roles y permisos (RBAC)

Un comercio se registra con el correo del administrador, que obtiene el rol de sistema **Administrador** con todos los permisos. En el módulo **Configuración** (`/settings`), los administradores editan los datos del comercio (nombre, razón social, RIF, moneda) y gestionan **roles personalizados** (nombre libre + permisos seleccionables) e **invitaciones de miembros por correo**; el invitado acepta la invitación al entrar con esa misma cuenta.

Los permisos son atómicos (`catalog.write`, `sales.checkout`, `purchasing.receive`, ...) y se aplican en tres capas: políticas RLS en PostgreSQL (`has_permission`), funciones transaccionales `SECURITY DEFINER` y dependencias FastAPI (`require_permissions`). Cada membrecía apunta a un `org_roles` con su lista de permisos; no existen roles fijos de sistema salvo el Administrador inicial.

## Próximos agregados

- `stock_movements`: ledger inmutable para entradas, salidas, ajustes y transferencias.
- `invoices` y `payments`: documentos con moneda, tasa y estado explícitos.
- `purchase_orders` y `goods_receipts`: pedir y recibir son acciones distintas.
- `ar_ledger` y `ap_ledger`: saldos separados por moneda.
