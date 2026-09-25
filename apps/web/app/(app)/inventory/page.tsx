"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

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
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type {
  Product,
  StockLevel,
  StockMovement,
  WarehouseRef,
} from "@/lib/types";
import { formatQty } from "@/lib/utils";

export default function InventoryPage() {
  const { orgId } = useOrg();

  const stock = useQuery({
    queryKey: ["stock", orgId],
    queryFn: () => api<StockLevel[]>(`/v1/inventory/stock`, { orgId }),
    enabled: !!orgId,
  });
  const movements = useQuery({
    queryKey: ["movements", orgId],
    queryFn: () =>
      api<StockMovement[]>(`/v1/inventory/movements?limit=50`, { orgId }),
    enabled: !!orgId,
  });

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
        Inventario
      </h1>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader title="Existencias" />
          {stock.isLoading ? (
            <LoadingState />
          ) : stock.isError ? (
            <ErrorState
              message={stock.error.message}
              onRetry={() => stock.refetch()}
            />
          ) : stock.data?.length === 0 ? (
            <EmptyState message="Sin existencias registradas." />
          ) : (
            <Table headers={["Producto", "SKU", "Almacén", "Cantidad"]}>
              {stock.data?.map((row) => (
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
          )}
        </Card>

        <AdjustmentForm />
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
        ) : movements.data?.length === 0 ? (
          <EmptyState message="Sin movimientos registrados." />
        ) : (
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
            {movements.data?.map((mov) => (
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
        )}
      </Card>
    </div>
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
