"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus } from "lucide-react";
import { useState } from "react";

import { Button, Card, CardHeader, EmptyState, ErrorState, Field, Input, LoadingState, Select, Table } from "@/components/ui";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type { Party, ReplenishmentItem, StockLevel } from "@/lib/types";
import { formatQty } from "@/lib/utils";

export default function ReplenishmentPage() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);

  const needed = useQuery({
    queryKey: ["replenishment", orgId],
    queryFn: () => api<ReplenishmentItem[]>(`/v1/replenishment/needed`, { orgId }),
    enabled: !!orgId,
  });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">Reposición</h1>
        <Button onClick={() => setOpen(true)}>
          <Plus className="h-4 w-4" />
          Configurar artículo
        </Button>
      </div>

      <Card>
        <CardHeader title="Artículos a pedir en el próximo pedido" />
        {needed.isLoading ? (
          <LoadingState />
        ) : needed.isError ? (
          <ErrorState message={needed.error.message} onRetry={() => needed.refetch()} />
        ) : needed.data?.length === 0 ? (
          <EmptyState message="No hay artículos bajo el mínimo. Configura niveles para activar la reposición." />
        ) : (
          <Table headers={["Producto", "SKU", "Almacén", "Existencia", "Pedido", "Mín", "Máx", "Sugerido"]}>
            {needed.data?.map((item) => (
              <tr key={`${item.variant_id}-${item.warehouse_id}`}>
                <td className="px-5 py-3 font-medium">{item.variant_name}</td>
                <td className="px-5 py-3 text-slate-600 dark:text-slate-400">{item.variant_sku}</td>
                <td className="px-5 py-3">{item.warehouse_name}</td>
                <td className="px-5 py-3">{formatQty(item.on_hand)}</td>
                <td className="px-5 py-3">{formatQty(item.on_order)}</td>
                <td className="px-5 py-3">{formatQty(item.min_qty)}</td>
                <td className="px-5 py-3">{formatQty(item.max_qty)}</td>
                <td className="px-5 py-3 font-semibold text-primary">{formatQty(item.suggested_qty)}</td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      {open && (
        <ConfigModal
          onClose={() => setOpen(false)}
          onSaved={() => {
            setOpen(false);
            queryClient.invalidateQueries({ queryKey: ["replenishment", orgId] });
          }}
        />
      )}
    </div>
  );
}

function ConfigModal({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { orgId } = useOrg();
  const [variantId, setVariantId] = useState("");
  const [warehouseId, setWarehouseId] = useState("");
  const [minQty, setMinQty] = useState("");
  const [maxQty, setMaxQty] = useState("");
  const [packMultiple, setPackMultiple] = useState("1");
  const [preferredSupplierId, setPreferredSupplierId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const stock = useQuery({
    queryKey: ["stock", orgId],
    queryFn: () => api<StockLevel[]>(`/v1/inventory/stock`, { orgId }),
    enabled: !!orgId,
  });
  const suppliers = useQuery({
    queryKey: ["parties", orgId, "supplier"],
    queryFn: () => api<Party[]>(`/v1/parties?kind=supplier`, { orgId }),
    enabled: !!orgId,
  });
  const warehouses = stock.data?.map((row) => row.warehouse).filter(Boolean) ?? [];

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await api("/v1/replenishment/config", {
        method: "PUT",
        orgId,
        body: {
          variant_id: variantId,
          warehouse_id: warehouseId,
          min_qty: Number(minQty),
          max_qty: Number(maxQty),
          pack_multiple: Number(packMultiple),
          preferred_supplier_id: preferredSupplierId || null,
          is_active: true,
        },
      });
      onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo guardar la configuración");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <form onSubmit={handleSubmit} className="mt-16 w-full max-w-md rounded-xl bg-white dark:bg-slate-800 shadow-lg">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">Configurar reposición</h2>
        </div>
        <div className="space-y-4 px-6 py-5">
          <Field label="Modelo">
            <Select value={variantId} onChange={(event) => setVariantId(event.target.value)} required>
              <option value="">Seleccionar...</option>
              {(stock.data ?? [])
                .map((row) => row.variant)
                .filter((v): v is NonNullable<typeof v> => !!v)
                .map((variant) => (
                  <option key={variant.id} value={variant.id}>
                    {variant.name} ({variant.sku})
                  </option>
                ))}
            </Select>
          </Field>
          <Field label="Almacén">
            <Select value={warehouseId} onChange={(event) => setWarehouseId(event.target.value)} required>
              <option value="">Seleccionar...</option>
              {warehouses.map((warehouse) => (
                <option key={warehouse!.id} value={warehouse!.id}>
                  {warehouse!.name}
                </option>
              ))}
            </Select>
          </Field>
          <div className="grid grid-cols-3 gap-4">
            <Field label="Mínimo">
              <Input type="number" step="0.001" min="0" value={minQty} onChange={(event) => setMinQty(event.target.value)} required />
            </Field>
            <Field label="Máximo">
              <Input type="number" step="0.001" min="0" value={maxQty} onChange={(event) => setMaxQty(event.target.value)} required />
            </Field>
            <Field label="Múltiplo">
              <Input type="number" step="0.001" min="0.001" value={packMultiple} onChange={(event) => setPackMultiple(event.target.value)} required />
            </Field>
          </div>
          <Field label="Proveedor preferido">
            <Select value={preferredSupplierId} onChange={(event) => setPreferredSupplierId(event.target.value)}>
              <option value="">Sin preferencia</option>
              {suppliers.data?.map((supplier) => (
                <option key={supplier.id} value={supplier.id}>
                  {supplier.name}
                </option>
              ))}
            </Select>
          </Field>
          {error && <p className="text-sm text-red-600">{error}</p>}
        </div>
        <div className="flex justify-end gap-3 border-t border-slate-200 dark:border-slate-700 px-6 py-4">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancelar
          </Button>
          <Button type="submit" disabled={submitting}>
            {submitting ? "Guardando..." : "Guardar"}
          </Button>
        </div>
      </form>
    </div>
  );
}