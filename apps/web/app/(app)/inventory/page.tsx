"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Pencil, Plus, Search, Trash2, X } from "lucide-react";
import { useMemo, useState } from "react";

import {
  Button,
  Card,
  CardHeader,
  EmptyState,
  ErrorState,
  Field,
  Input,
  LoadingState,
  Select,
  Table,
} from "@/components/ui";
import { useFeedback } from "@/components/feedback";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type {
  Product,
  StockLevel,
  StockMovement,
  WarehouseRef,
} from "@/lib/types";
import { formatQty } from "@/lib/utils";

const PAGE_SIZE = 12;

function usePagination<T>(items: T[]) {
  const [page, setPage] = useState(1);
  const totalPages = Math.max(1, Math.ceil(items.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);
  const start = (safePage - 1) * PAGE_SIZE;
  const pageItems = items.slice(start, start + PAGE_SIZE);
  return { page: safePage, totalPages, pageItems, setPage };
}

function Pagination({
  page,
  totalPages,
  setPage,
}: {
  page: number;
  totalPages: number;
  setPage: (page: number) => void;
}) {
  if (totalPages <= 1) return null;
  return (
    <div className="flex items-center justify-between border-t border-slate-200 px-5 py-3 dark:border-slate-700">
      <span className="text-xs text-slate-500 dark:text-slate-400">
        Página {page} de {totalPages}
      </span>
      <div className="flex items-center gap-2">
        <Button
          variant="secondary"
          className="px-3 py-1 text-xs"
          disabled={page <= 1}
          onClick={() => setPage(page - 1)}
        >
          Anterior
        </Button>
        <Button
          variant="secondary"
          className="px-3 py-1 text-xs"
          disabled={page >= totalPages}
          onClick={() => setPage(page + 1)}
        >
          Siguiente
        </Button>
      </div>
    </div>
  );
}

export default function InventoryPage() {
  const { orgId } = useOrg();

  const movements = useQuery({
    queryKey: ["movements", orgId],
    queryFn: () =>
      api<StockMovement[]>(`/v1/inventory/movements?limit=500`, { orgId }),
    enabled: !!orgId,
  });

  const pagination = usePagination(movements.data ?? []);

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
        Inventario
      </h1>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <WarehousesCard />
        <StockCard />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <AdjustmentForm />
        <TransferForm />
      </div>

      <Card>
        <CardHeader title="Movimientos recientes" />
        {movements.isLoading ? (
          <LoadingState />
        ) : movements.isError ? (
          <ErrorState
            message={movements.error.message}
            onRetry={() => movements.refetch()}
          />
        ) : (movements.data ?? []).length === 0 ? (
          <EmptyState message="Sin movimientos registrados." />
        ) : (
          <>
            <Table
              headers={[
                "Fecha",
                "Producto",
                "Almacén",
                "Tipo",
                "Cantidad",
                "Saldo",
                "Motivo",
              ]}
            >
              {pagination.pageItems.map((mov) => (
                <tr key={mov.id}>
                  <td className="px-5 py-3 text-slate-600 dark:text-slate-400">
                    {new Date(mov.created_at).toLocaleString()}
                  </td>
                  <td className="px-5 py-3 font-medium">
                    {mov.variant?.name ?? mov.variant_id}
                  </td>
                  <td className="px-5 py-3">{mov.warehouse?.name}</td>
                  <td className="px-5 py-3">
                    <span
                      className={
                        Number(mov.qty) > 0 ? "text-green-600" : "text-red-600"
                      }
                    >
                      {mov.movement_type}
                    </span>
                  </td>
                  <td className="px-5 py-3 font-semibold">
                    {formatQty(mov.qty)}
                  </td>
                  <td className="px-5 py-3">{formatQty(mov.balance_after)}</td>
                  <td className="px-5 py-3 text-slate-600 dark:text-slate-400">
                    {mov.reason}
                  </td>
                </tr>
              ))}
            </Table>
            <Pagination {...pagination} />
          </>
        )}
      </Card>
    </div>
  );
}

function WarehousesCard() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const { notify, confirm } = useFeedback();
  const [createOpen, setCreateOpen] = useState(false);
  const [editing, setEditing] = useState<WarehouseRef | null>(null);

  const warehouses = useQuery({
    queryKey: ["warehouses", orgId],
    queryFn: () => api<WarehouseRef[]>(`/v1/inventory/warehouses`, { orgId }),
    enabled: !!orgId,
  });

  const pagination = usePagination(warehouses.data ?? []);

  async function handleDelete(warehouse: WarehouseRef) {
    const ok = await confirm(
      `¿Borrar el almacén "${warehouse.name}"? Se ocultará y no podrá usarse en POS ni traslados.`,
    );
    if (!ok) return;
    try {
      await api(`/v1/inventory/warehouses/${warehouse.id}`, {
        method: "DELETE",
        orgId,
      });
      notify("Almacén borrado.", "success");
      queryClient.invalidateQueries({ queryKey: ["warehouses", orgId] });
      queryClient.invalidateQueries({ queryKey: ["stock", orgId] });
    } catch (err) {
      notify(
        err instanceof Error ? err.message : "No se pudo borrar el almacén",
      );
    }
  }

  return (
    <Card>
      <CardHeader
        title="Almacenes"
        action={
          <Button
            onClick={() => setCreateOpen(true)}
            className="px-3 py-1.5 text-xs"
          >
            <Plus className="h-3.5 w-3.5" />
            Nuevo almacén
          </Button>
        }
      />
      {warehouses.isLoading ? (
        <LoadingState />
      ) : warehouses.isError ? (
        <ErrorState
          message={warehouses.error.message}
          onRetry={() => warehouses.refetch()}
        />
      ) : (warehouses.data ?? []).length === 0 ? (
        <EmptyState message="Sin almacenes. Crea el primero." />
      ) : (
        <>
          <div className="divide-y divide-slate-100 dark:divide-slate-800">
            {pagination.pageItems.map((wh) => (
              <div
                key={wh.id}
                className="flex items-center justify-between px-5 py-3"
              >
                <div>
                  <div className="text-sm font-medium text-slate-900 dark:text-slate-100">
                    {wh.name}
                  </div>
                  <div className="text-xs text-slate-500 dark:text-slate-400">
                    {wh.code}
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => setEditing(wh)}
                    aria-label={`Editar ${wh.name}`}
                    className="rounded-lg p-1.5 text-slate-500 hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-slate-700"
                  >
                    <Pencil className="h-4 w-4" />
                  </button>
                  <button
                    onClick={() => handleDelete(wh)}
                    aria-label={`Borrar ${wh.name}`}
                    className="rounded-lg p-1.5 text-slate-500 hover:bg-red-50 hover:text-red-600 dark:text-slate-400 dark:hover:bg-red-900/20"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
              </div>
            ))}
          </div>
          <Pagination {...pagination} />
        </>
      )}
      {(createOpen || editing) && (
        <WarehouseModal
          orgId={orgId}
          warehouse={editing}
          onClose={() => {
            setCreateOpen(false);
            setEditing(null);
          }}
          onSaved={() => {
            setCreateOpen(false);
            setEditing(null);
            queryClient.invalidateQueries({ queryKey: ["warehouses", orgId] });
            notify(
              editing ? "Almacén actualizado." : "Almacén creado.",
              "success",
            );
          }}
          notify={notify}
        />
      )}
    </Card>
  );
}

function WarehouseModal({
  orgId,
  warehouse,
  onClose,
  onSaved,
  notify,
}: {
  orgId: string | null;
  warehouse: WarehouseRef | null;
  onClose: () => void;
  onSaved: () => void;
  notify: (message: string, type?: "success" | "error") => void;
}) {
  const [name, setName] = useState(warehouse?.name ?? "");
  const [code, setCode] = useState(warehouse?.code ?? "");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setLoading(true);
    try {
      if (warehouse) {
        await api(`/v1/inventory/warehouses/${warehouse.id}`, {
          method: "PATCH",
          orgId,
          body: { name, code },
        });
      } else {
        await api("/v1/inventory/warehouses", {
          method: "POST",
          orgId,
          body: { name, code },
        });
      }
      onSaved();
    } catch (err) {
      notify(
        err instanceof Error ? err.message : "No se pudo guardar el almacén",
      );
      setLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4 sm:py-8">
      <div className="w-full max-w-md rounded-xl bg-white shadow-xl dark:bg-slate-800">
        <div className="flex items-center justify-between border-b border-slate-200 px-6 py-4 dark:border-slate-700">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
            {warehouse ? "Editar almacén" : "Nuevo almacén"}
          </h2>
          <button
            onClick={onClose}
            aria-label="Cerrar"
            className="rounded-lg p-1 text-slate-500 hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-slate-700"
          >
            <X className="h-5 w-5" />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4 px-6 py-5">
          <Field label="Nombre">
            <Input
              required
              maxLength={120}
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="Almacén Central"
            />
          </Field>
          <Field label="Código">
            <Input
              required
              maxLength={20}
              value={code}
              onChange={(event) => setCode(event.target.value)}
              placeholder="ALM02"
            />
          </Field>
          <div className="flex justify-end gap-3 border-t border-slate-200 pt-4 dark:border-slate-700">
            <Button
              type="button"
              variant="secondary"
              onClick={onClose}
              disabled={loading}
            >
              Cancelar
            </Button>
            <Button type="submit" disabled={loading}>
              {loading
                ? "Guardando..."
                : warehouse
                  ? "Guardar cambios"
                  : "Crear almacén"}
            </Button>
          </div>
        </form>
      </div>
    </div>
  );
}

function StockCard() {
  const { orgId } = useOrg();
  const [warehouseId, setWarehouseId] = useState("");
  const [query, setQuery] = useState("");

  const stock = useQuery({
    queryKey: ["stock", orgId],
    queryFn: () => api<StockLevel[]>(`/v1/inventory/stock`, { orgId }),
    enabled: !!orgId,
  });
  const warehouses = useQuery({
    queryKey: ["warehouses", orgId],
    queryFn: () => api<WarehouseRef[]>(`/v1/inventory/warehouses`, { orgId }),
    enabled: !!orgId,
  });

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    let rows = stock.data ?? [];
    if (warehouseId) rows = rows.filter((r) => r.warehouse_id === warehouseId);
    if (!q) return rows;
    return rows.filter(
      (r) =>
        (r.variant?.name ?? "").toLowerCase().includes(q) ||
        (r.variant?.sku ?? "").toLowerCase().includes(q) ||
        (r.warehouse?.name ?? "").toLowerCase().includes(q),
    );
  }, [stock.data, warehouseId, query]);

  const pagination = usePagination(filtered);

  return (
    <Card>
      <CardHeader
        title="Existencias"
        action={
          <Select
            value={warehouseId}
            onChange={(event) => setWarehouseId(event.target.value)}
            className="w-44"
          >
            <option value="">Todos los almacenes</option>
            {(warehouses.data ?? []).map((wh) => (
              <option key={wh.id} value={wh.id}>
                {wh.name}
              </option>
            ))}
          </Select>
        }
      />
      <div className="px-5 py-3">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
          <Input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Buscar artículo por nombre, SKU o almacén..."
            className="pl-9"
          />
        </div>
      </div>
      {stock.isLoading ? (
        <LoadingState />
      ) : stock.isError ? (
        <ErrorState message={stock.error.message} onRetry={stock.refetch} />
      ) : filtered.length === 0 ? (
        <EmptyState message="Sin existencias registradas." />
      ) : (
        <>
          <Table headers={["Producto", "SKU", "Almacén", "Cantidad"]}>
            {pagination.pageItems.map((row) => (
              <tr key={row.id}>
                <td className="px-5 py-3 font-medium">
                  {row.variant?.name ?? row.variant_id}
                </td>
                <td className="px-5 py-3 text-slate-600 dark:text-slate-400">
                  {row.variant?.sku}
                </td>
                <td className="px-5 py-3">
                  {row.warehouse?.name ?? row.warehouse_id}
                </td>
                <td className="px-5 py-3 font-semibold">
                  {formatQty(row.qty)}
                </td>
              </tr>
            ))}
          </Table>
          <Pagination {...pagination} />
        </>
      )}
    </Card>
  );
}

function AdjustmentForm() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const [variantId, setVariantId] = useState("");
  const [warehouseId, setWarehouseId] = useState("");
  const [delta, setDelta] = useState("");
  const [reason, setReason] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const warehouses = useQuery({
    queryKey: ["warehouses", orgId],
    queryFn: () => api<WarehouseRef[]>(`/v1/inventory/warehouses`, { orgId }),
    enabled: !!orgId,
  });
  const products = useQuery({
    queryKey: ["catalog", orgId],
    queryFn: () => api<Product[]>(`/v1/catalog/products`, { orgId }),
    enabled: !!orgId,
  });

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    setMessage(null);
    try {
      await api(`/v1/inventory/adjustments`, {
        method: "POST",
        orgId,
        body: {
          variant_id: variantId,
          warehouse_id: warehouseId,
          delta: Number(delta),
          reason: reason || null,
        },
      });
      setMessage("Ajuste registrado correctamente.");
      setDelta("");
      setReason("");
      queryClient.invalidateQueries({ queryKey: ["stock", orgId] });
      queryClient.invalidateQueries({ queryKey: ["movements", orgId] });
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "No se pudo registrar el ajuste",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Card>
      <CardHeader title="Ajuste de inventario" />
      <form onSubmit={handleSubmit} className="space-y-4 px-5 py-4">
        <Field label="Modelo (variante)">
          <Select
            value={variantId}
            onChange={(event) => setVariantId(event.target.value)}
            required
          >
            <option value="">Seleccionar...</option>
            {(products.data ?? [])
              .flatMap((product) => product.product_variants)
              .map((variant) => (
                <option key={variant.id} value={variant.id}>
                  {variant.name} ({variant.sku})
                </option>
              ))}
          </Select>
        </Field>
        <Field label="Almacén">
          <Select
            value={warehouseId}
            onChange={(event) => setWarehouseId(event.target.value)}
            required
          >
            <option value="">Seleccionar...</option>
            {warehouses.data?.map((warehouse) => (
              <option key={warehouse.id} value={warehouse.id}>
                {warehouse.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Cantidad (positiva para entrada, negativa para salida)">
          <Input
            type="number"
            step="0.01"
            required
            value={delta}
            onChange={(event) => setDelta(event.target.value)}
          />
        </Field>
        <Field label="Motivo">
          <Input
            value={reason}
            onChange={(event) => setReason(event.target.value)}
          />
        </Field>
        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}
        <Button type="submit" disabled={submitting}>
          {submitting ? "Registrando..." : "Registrar ajuste"}
        </Button>
      </form>
    </Card>
  );
}

function TransferForm() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const { notify } = useFeedback();
  const [variantId, setVariantId] = useState("");
  const [fromWarehouseId, setFromWarehouseId] = useState("");
  const [toWarehouseId, setToWarehouseId] = useState("");
  const [qty, setQty] = useState("");
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const warehouses = useQuery({
    queryKey: ["warehouses", orgId],
    queryFn: () => api<WarehouseRef[]>(`/v1/inventory/warehouses`, { orgId }),
    enabled: !!orgId,
  });
  const products = useQuery({
    queryKey: ["catalog", orgId],
    queryFn: () => api<Product[]>(`/v1/catalog/products`, { orgId }),
    enabled: !!orgId,
  });

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await api(`/v1/inventory/transfers`, {
        method: "POST",
        orgId,
        body: {
          variant_id: variantId,
          from_warehouse_id: fromWarehouseId,
          to_warehouse_id: toWarehouseId,
          qty: Number(qty),
          reason: reason || null,
        },
      });
      notify("Traslado registrado.", "success");
      setQty("");
      setReason("");
      queryClient.invalidateQueries({ queryKey: ["stock", orgId] });
      queryClient.invalidateQueries({ queryKey: ["movements", orgId] });
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "No se pudo registrar el traslado",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Card>
      <CardHeader title="Traslado entre almacenes" />
      <form onSubmit={handleSubmit} className="space-y-4 px-5 py-4">
        <Field label="Modelo (variante)">
          <Select
            value={variantId}
            onChange={(event) => setVariantId(event.target.value)}
            required
          >
            <option value="">Seleccionar...</option>
            {(products.data ?? [])
              .flatMap((product) => product.product_variants)
              .map((variant) => (
                <option key={variant.id} value={variant.id}>
                  {variant.name} ({variant.sku})
                </option>
              ))}
          </Select>
        </Field>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="Origen">
            <Select
              value={fromWarehouseId}
              onChange={(event) => setFromWarehouseId(event.target.value)}
              required
            >
              <option value="">Seleccionar...</option>
              {(warehouses.data ?? []).map((warehouse) => (
                <option key={warehouse.id} value={warehouse.id}>
                  {warehouse.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Destino">
            <Select
              value={toWarehouseId}
              onChange={(event) => setToWarehouseId(event.target.value)}
              required
            >
              <option value="">Seleccionar...</option>
              {(warehouses.data ?? []).map((warehouse) => (
                <option key={warehouse.id} value={warehouse.id}>
                  {warehouse.name}
                </option>
              ))}
            </Select>
          </Field>
        </div>
        <Field label="Cantidad">
          <Input
            type="number"
            step="0.01"
            required
            min="0.01"
            value={qty}
            onChange={(event) => setQty(event.target.value)}
          />
        </Field>
        <Field label="Motivo (opcional)">
          <Input
            value={reason}
            onChange={(event) => setReason(event.target.value)}
          />
        </Field>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <Button type="submit" disabled={submitting}>
          {submitting ? "Trasladando..." : "Registrar traslado"}
        </Button>
      </form>
    </Card>
  );
}
