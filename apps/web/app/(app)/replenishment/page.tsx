"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Pencil, Plus, Trash2 } from "lucide-react";
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
  Modal,
  Select,
  Table,
} from "@/components/ui";
import { useFeedback } from "@/components/feedback";
import { Pagination, usePagination } from "@/components/pagination";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type {
  Party,
  Product,
  ReplenishmentConfig,
  ReplenishmentItem,
  WarehouseRef,
} from "@/lib/types";
import { formatQty } from "@/lib/utils";

export default function ReplenishmentPage() {
  const { orgId } = useOrg();
  const { confirm } = useFeedback();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<ReplenishmentConfig | null>(null);

  const needed = useQuery({
    queryKey: ["replenishment", orgId],
    queryFn: () =>
      api<ReplenishmentItem[]>(`/v1/replenishment/needed`, { orgId }),
    enabled: !!orgId,
  });

  const configs = useQuery({
    queryKey: ["replenishment-configs", orgId],
    queryFn: () =>
      api<ReplenishmentConfig[]>(`/v1/replenishment/configs`, { orgId }),
    enabled: !!orgId,
  });

  const neededPagination = usePagination(needed.data ?? []);
  const configsPagination = usePagination(configs.data ?? []);

  async function handleDelete(config: ReplenishmentConfig) {
    if (
      !(await confirm(
        `¿Eliminar la configuración de "${config.variant?.name}"?`,
      ))
    )
      return;
    await api(`/v1/replenishment/config/${config.id}`, {
      method: "DELETE",
      orgId,
    });
    queryClient.invalidateQueries({
      queryKey: ["replenishment-configs", orgId],
    });
    queryClient.invalidateQueries({ queryKey: ["replenishment", orgId] });
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
          Reposición
        </h1>
        <Button
          onClick={() => {
            setEditing(null);
            setOpen(true);
          }}
        >
          <Plus className="h-4 w-4" />
          Configurar artículo
        </Button>
      </div>

      <Card>
        <CardHeader title="Artículos a pedir en el próximo pedido" />
        {needed.isLoading ? (
          <LoadingState />
        ) : needed.isError ? (
          <ErrorState
            message={needed.error.message}
            onRetry={() => needed.refetch()}
          />
        ) : needed.data?.length === 0 ? (
          <EmptyState message="No hay artículos bajo el mínimo. Configura niveles para activar la reposición." />
        ) : (
          <>
            <Table
              headers={[
                "Producto",
                "SKU",
                "Almacén",
                "Existencia",
                "Pedido",
                "Mín",
                "Máx",
                "Sugerido",
              ]}
            >
              {neededPagination.pageItems.map((item) => (
                <tr key={`${item.variant_id}-${item.warehouse_id}`}>
                  <td className="px-5 py-3 font-medium">{item.variant_name}</td>
                  <td className="px-5 py-3 text-slate-600 dark:text-slate-400">
                    {item.variant_sku}
                  </td>
                  <td className="px-5 py-3">{item.warehouse_name}</td>
                  <td className="px-5 py-3">{formatQty(item.on_hand)}</td>
                  <td className="px-5 py-3">{formatQty(item.on_order)}</td>
                  <td className="px-5 py-3">{formatQty(item.min_qty)}</td>
                  <td className="px-5 py-3">{formatQty(item.max_qty)}</td>
                  <td className="px-5 py-3 font-semibold text-primary">
                    {formatQty(item.suggested_qty)}
                  </td>
                </tr>
              ))}
            </Table>
            <Pagination {...neededPagination} />
          </>
        )}
      </Card>

      <Card>
        <CardHeader title="Configuraciones de reposición" />
        {configs.isLoading ? (
          <LoadingState />
        ) : configs.isError ? (
          <ErrorState
            message={configs.error.message}
            onRetry={() => configs.refetch()}
          />
        ) : configs.data?.length === 0 ? (
          <EmptyState message="Sin configuraciones. Agrega una para activar la reposición." />
        ) : (
          <>
            <Table
              headers={[
                "Modelo",
                "SKU",
                "Almacén",
                "Mín",
                "Máx",
                "Múltiplo",
                "Estado",
                "",
              ]}
            >
              {configsPagination.pageItems.map((config) => (
                <tr key={config.id}>
                  <td className="px-5 py-3 font-medium">
                    {config.variant?.name}
                  </td>
                  <td className="px-5 py-3 text-slate-600 dark:text-slate-400">
                    {config.variant?.sku}
                  </td>
                  <td className="px-5 py-3">{config.warehouse?.name}</td>
                  <td className="px-5 py-3">{formatQty(config.min_qty)}</td>
                  <td className="px-5 py-3">{formatQty(config.max_qty)}</td>
                  <td className="px-5 py-3">
                    {formatQty(config.pack_multiple)}
                  </td>
                  <td className="px-5 py-3">
                    <span
                      className={
                        config.is_active ? "text-green-600" : "text-slate-400"
                      }
                    >
                      {config.is_active ? "Activa" : "Inactiva"}
                    </span>
                  </td>
                  <td className="px-5 py-3">
                    <div className="flex justify-end gap-1">
                      <Button
                        variant="ghost"
                        className="px-2 py-1"
                        onClick={() => {
                          setEditing(config);
                          setOpen(true);
                        }}
                        aria-label="Editar"
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        className="px-2 py-1 text-red-600"
                        onClick={() => handleDelete(config)}
                        aria-label="Eliminar"
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </Table>
            <Pagination {...configsPagination} />
          </>
        )}
      </Card>

      {open && (
        <ConfigModal
          config={editing}
          onClose={() => setOpen(false)}
          onSaved={() => {
            setOpen(false);
            setEditing(null);
            queryClient.invalidateQueries({
              queryKey: ["replenishment-configs", orgId],
            });
            queryClient.invalidateQueries({
              queryKey: ["replenishment", orgId],
            });
          }}
        />
      )}
    </div>
  );
}

function ConfigModal({
  config,
  onClose,
  onSaved,
}: {
  config: ReplenishmentConfig | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { orgId } = useOrg();
  const [variantId, setVariantId] = useState(config?.variant_id ?? "");
  const [warehouseId, setWarehouseId] = useState(config?.warehouse_id ?? "");
  const [minQty, setMinQty] = useState(config?.min_qty ?? "");
  const [maxQty, setMaxQty] = useState(config?.max_qty ?? "");
  const [packMultiple, setPackMultiple] = useState(
    config?.pack_multiple ?? "1",
  );
  const [preferredSupplierId, setPreferredSupplierId] = useState(
    config?.preferred_supplier_id ?? "",
  );
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const products = useQuery({
    queryKey: ["catalog", orgId],
    queryFn: () => api<Product[]>(`/v1/catalog/products`, { orgId }),
    enabled: !!orgId,
  });
  const warehouses = useQuery({
    queryKey: ["warehouses", orgId],
    queryFn: () => api<WarehouseRef[]>(`/v1/inventory/warehouses`, { orgId }),
    enabled: !!orgId,
  });
  const suppliers = useQuery({
    queryKey: ["parties", orgId, "supplier"],
    queryFn: () => api<Party[]>(`/v1/parties?kind=supplier`, { orgId }),
    enabled: !!orgId,
  });

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const body = {
        variant_id: variantId,
        warehouse_id: warehouseId,
        min_qty: Number(minQty),
        max_qty: Number(maxQty),
        pack_multiple: Number(packMultiple),
        preferred_supplier_id: preferredSupplierId || null,
        is_active: true,
      };
      if (config) {
        await api(`/v1/replenishment/config/${config.id}`, {
          method: "PATCH",
          orgId,
          body,
        });
      } else {
        await api("/v1/replenishment/config", { method: "PUT", orgId, body });
      }
      onSaved();
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "No se pudo guardar la configuración",
      );
      setSubmitting(false);
    }
  }

  return (
    <Modal
      title={config ? "Editar reposición" : "Configurar reposición"}
      onClose={onClose}
      footer={
        <>
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancelar
          </Button>
          <Button
            type="submit"
            form="replenish-config-form"
            disabled={submitting}
          >
            {submitting ? "Guardando..." : "Guardar"}
          </Button>
        </>
      }
    >
      <form
        onSubmit={handleSubmit}
        id="replenish-config-form"
        className="space-y-4"
      >
        <Field label="Modelo">
          <Select
            className="w-full"
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
            className="w-full"
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
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <Field label="Mínimo">
            <Input
              type="number"
              step="0.01"
              min="0"
              value={minQty}
              onChange={(event) => setMinQty(event.target.value)}
              required
            />
          </Field>
          <Field label="Máximo">
            <Input
              type="number"
              step="0.01"
              min="0"
              value={maxQty}
              onChange={(event) => setMaxQty(event.target.value)}
              required
            />
          </Field>
          <Field label="Múltiplo">
            <Input
              type="number"
              step="0.01"
              min="0.001"
              value={packMultiple}
              onChange={(event) => setPackMultiple(event.target.value)}
              required
            />
          </Field>
        </div>
        <Field label="Proveedor preferido">
          <Select
            className="w-full"
            value={preferredSupplierId}
            onChange={(event) => setPreferredSupplierId(event.target.value)}
          >
            <option value="">Sin preferencia</option>
            {suppliers.data?.map((supplier) => (
              <option key={supplier.id} value={supplier.id}>
                {supplier.name}
              </option>
            ))}
          </Select>
        </Field>
        {error && <p className="text-sm text-red-600">{error}</p>}
      </form>
    </Modal>
  );
}
