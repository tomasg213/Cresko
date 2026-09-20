"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus } from "lucide-react";
import { useState } from "react";

import { Button, Card, CardHeader, EmptyState, ErrorState, Field, Input, LoadingState, Select, Table } from "@/components/ui";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type { Party, PurchaseOrder, StockLevel } from "@/lib/types";
import { formatMoney, formatQty } from "@/lib/utils";

type PoRow = { variant_id: string; qty: string; unit_cost: string };

export default function PurchasingPage() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);

  const orders = useQuery({
    queryKey: ["purchase-orders", orgId],
    queryFn: () => api<PurchaseOrder[]>(`/v1/purchasing/orders`, { orgId }),
    enabled: !!orgId,
  });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">Órdenes de compra</h1>
        <Button onClick={() => setOpen(true)}>
          <Plus className="h-4 w-4" />
          Nueva orden
        </Button>
      </div>

      <Card>
        <CardHeader title="Órdenes" />
        {orders.isLoading ? (
          <LoadingState />
        ) : orders.isError ? (
          <ErrorState message={orders.error.message} onRetry={() => orders.refetch()} />
        ) : orders.data?.length === 0 ? (
          <EmptyState message="Sin órdenes de compra." />
        ) : (
          <Table headers={["Número", "Estado", "Moneda", "Líneas", "Creada"]}>
            {orders.data?.map((order) => (
              <tr key={order.id}>
                <td className="px-5 py-3 font-medium">{order.number}</td>
                <td className="px-5 py-3">
                  <span
                    className={
                      order.status === "received"
                        ? "text-green-600"
                        : order.status === "partial"
                          ? "text-amber-600"
                          : "text-slate-600 dark:text-slate-400"
                    }
                  >
                    {order.status}
                  </span>
                </td>
                <td className="px-5 py-3">{order.currency}</td>
                <td className="px-5 py-3">{order.po_lines.length}</td>
                <td className="px-5 py-3 text-slate-600 dark:text-slate-400">{new Date(order.created_at).toLocaleDateString()}</td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      {open && (
        <CreateOrderModal
          onClose={() => setOpen(false)}
          onCreated={() => {
            setOpen(false);
            queryClient.invalidateQueries({ queryKey: ["purchase-orders", orgId] });
          }}
        />
      )}
    </div>
  );
}

function CreateOrderModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const [supplierId, setSupplierId] = useState("");
  const [warehouseId, setWarehouseId] = useState("");
  const [currency, setCurrency] = useState<"VES" | "USD">("VES");
  const [lines, setLines] = useState<PoRow[]>([{ variant_id: "", qty: "", unit_cost: "" }]);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const suppliers = useQuery({
    queryKey: ["parties", orgId, "supplier"],
    queryFn: () => api<Party[]>(`/v1/parties?kind=supplier`, { orgId }),
    enabled: !!orgId,
  });
  const stock = useQuery({
    queryKey: ["stock", orgId],
    queryFn: () => api<StockLevel[]>(`/v1/inventory/stock`, { orgId }),
    enabled: !!orgId,
  });
  const warehouses = stock.data?.map((row) => row.warehouse).filter(Boolean) ?? [];

  function updateLine(index: number, patch: Partial<PoRow>) {
    setLines((current) => current.map((line, i) => (i === index ? { ...line, ...patch } : line)));
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await api("/v1/purchasing/orders", {
        method: "POST",
        orgId,
        body: {
          supplier_id: supplierId,
          warehouse_id: warehouseId,
          currency,
          lines: lines.map((line) => ({
            variant_id: line.variant_id,
            qty: Number(line.qty),
            unit_cost: Number(line.unit_cost),
          })),
        },
      });
      onCreated();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo crear la orden");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <form onSubmit={handleSubmit} className="mt-8 w-full max-w-2xl rounded-xl bg-white dark:bg-slate-800 shadow-lg">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">Nueva orden de compra</h2>
        </div>
        <div className="space-y-4 px-6 py-5">
          <div className="grid grid-cols-3 gap-4">
            <Field label="Proveedor">
              <Select required value={supplierId} onChange={(event) => setSupplierId(event.target.value)}>
                <option value="">Seleccionar...</option>
                {suppliers.data?.map((supplier) => (
                  <option key={supplier.id} value={supplier.id}>
                    {supplier.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Almacén destino">
              <Select required value={warehouseId} onChange={(event) => setWarehouseId(event.target.value)}>
                <option value="">Seleccionar...</option>
                {warehouses.map((warehouse) => (
                  <option key={warehouse!.id} value={warehouse!.id}>
                    {warehouse!.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Moneda">
              <Select value={currency} onChange={(event) => setCurrency(event.target.value as "VES" | "USD")}>
                <option value="VES">Bs.</option>
                <option value="USD">$</option>
              </Select>
            </Field>
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold text-slate-700 dark:text-slate-200">Productos</h3>
              <Button type="button" variant="secondary" onClick={() => setLines([...lines, { variant_id: "", qty: "", unit_cost: "" }])}>
                Agregar línea
              </Button>
            </div>
            {lines.map((line, index) => (
              <div key={index} className="grid grid-cols-3 gap-3 rounded-lg border border-slate-200 dark:border-slate-700 p-3">
                <Field label="Modelo">
                  <Select value={line.variant_id} onChange={(event) => updateLine(index, { variant_id: event.target.value })} required>
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
                <Field label="Cantidad">
                  <Input type="number" step="0.001" min="0" value={line.qty} onChange={(event) => updateLine(index, { qty: event.target.value })} required />
                </Field>
                <Field label="Costo unitario">
                  <Input type="number" step="0.01" min="0" value={line.unit_cost} onChange={(event) => updateLine(index, { unit_cost: event.target.value })} required />
                </Field>
              </div>
            ))}
          </div>

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