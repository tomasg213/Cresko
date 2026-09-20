"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Pencil, Plus, Trash2 } from "lucide-react";
import { useState } from "react";

import { Button, Card, CardHeader, EmptyState, ErrorState, Field, Input, LoadingState, Select, Table } from "@/components/ui";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type { Product } from "@/lib/types";
import { formatMoney } from "@/lib/utils";

type PriceRow = { price_list_code: "retail" | "wholesale"; amount: string };
type VariantRow = { variant_id?: string; sku: string; name: string; barcode: string; prices: PriceRow[] };
type ModalState = { mode: "create" } | { mode: "edit"; product: Product } | null;

export default function CatalogPage() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const [modal, setModal] = useState<ModalState>(null);

  const products = useQuery({
    queryKey: ["products", orgId],
    queryFn: () => api<Product[]>(`/v1/catalog/products`, { orgId }),
    enabled: !!orgId,
  });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">Catálogo</h1>
        <Button onClick={() => setModal({ mode: "create" })}>
          <Plus className="h-4 w-4" />
          Nuevo artículo
        </Button>
      </div>

      <Card>
        <CardHeader title="Artículos" />
        {products.isLoading ? (
          <LoadingState />
        ) : products.isError ? (
          <ErrorState message={products.error.message} onRetry={() => products.refetch()} />
        ) : products.data?.length === 0 ? (
          <EmptyState message="Aún no hay artículos. Crea el primero." />
        ) : (
          <Table headers={["Artículo", "Modelos", "Precios", "Estado", "Acciones"]}>
            {products.data?.map((product) => (
              <tr key={product.id}>
                <td className="px-5 py-3 font-medium">{product.name}</td>
                <td className="px-5 py-3">{product.product_variants.length}</td>
                <td className="px-5 py-3">
                  {product.product_variants.flatMap((v) => v.variant_prices).slice(0, 2).map((p, i) => (
                    <div key={i} className="text-xs text-slate-600 dark:text-slate-400">
                      {formatMoney(p.amount, p.currency)}
                    </div>
                  ))}
                </td>
                <td className="px-5 py-3">
                  <span className={product.is_active ? "text-green-600" : "text-slate-400"}>
                    {product.is_active ? "Activo" : "Inactivo"}
                  </span>
                </td>
                <td className="px-5 py-3">
                  <div className="flex items-center gap-2">
                    <Button variant="secondary" onClick={() => setModal({ mode: "edit", product })}>
                      <Pencil className="h-4 w-4" />
                      Editar
                    </Button>
                    <Button
                      variant="danger"
                      onClick={async () => {
                        if (!window.confirm(`¿Eliminar "${product.name}"? Esta acción no se puede deshacer.`)) return;
                        try {
                          await api(`/v1/catalog/products/${product.id}`, { method: "DELETE", orgId });
                          queryClient.invalidateQueries({ queryKey: ["products", orgId] });
                          queryClient.invalidateQueries({ queryKey: ["catalog", orgId] });
                        } catch (err) {
                          window.alert(err instanceof Error ? err.message : "No se pudo eliminar el artículo");
                        }
                      }}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      {modal && (
        <ProductModal
          initial={modal.mode === "edit" ? modal.product : null}
          onClose={() => setModal(null)}
          onSaved={() => {
            setModal(null);
            queryClient.invalidateQueries({ queryKey: ["products", orgId] });
          }}
        />
      )}
    </div>
  );
}

function ProductModal({
  initial,
  onClose,
  onSaved,
}: {
  initial: Product | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { orgId } = useOrg();
  const editing = initial !== null;

  const initialVariants: VariantRow[] = editing
    ? (initial?.product_variants ?? []).map((variant) => ({
        variant_id: variant.id,
        sku: variant.sku,
        name: variant.name,
        barcode: variant.barcodes[0]?.barcode ?? "",
        prices: (["retail", "wholesale"] as const).map((code) => {
          const price = variant.variant_prices.find(
            (p) => p.currency === "USD" && (p.price_list?.code ?? "retail") === code,
          );
          return { price_list_code: code, amount: price ? String(price.amount) : "" };
        }),
      }))
    : [];

  const [name, setName] = useState(initial?.name ?? "");
  const [description, setDescription] = useState(initial?.description ?? "");
  const [baseUnit, setBaseUnit] = useState(initial?.base_unit ?? "unit");
  const [isTaxable, setIsTaxable] = useState(initial?.is_taxable ?? true);
  const [variants, setVariants] = useState<VariantRow[]>(
    editing
      ? initialVariants
      : [{ sku: "", name: "", barcode: "", prices: [{ price_list_code: "retail", amount: "" }] }],
  );
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  function updateVariant(index: number, patch: Partial<VariantRow>) {
    setVariants((current) => current.map((v, i) => (i === index ? { ...v, ...patch } : v)));
  }

  function updatePrice(variantIndex: number, priceIndex: number, patch: Partial<PriceRow>) {
    setVariants((current) =>
      current.map((v, i) =>
        i === variantIndex
          ? {
              ...v,
              prices: v.prices.map((p, pi) => (pi === priceIndex ? { ...p, ...patch } : p)),
            }
          : v,
      ),
    );
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    const pricesPayload = (v: VariantRow) =>
      v.prices
        .filter((p) => p.amount !== "")
        .map((p) => ({ price_list_code: p.price_list_code, amount: Number(p.amount) }));

    try {
      if (editing) {
        await api(`/v1/catalog/products/${initial.id}`, {
          method: "PATCH",
          orgId,
          body: {
            name,
            description: description || null,
            base_unit: baseUnit,
            is_taxable: isTaxable,
            variants: variants.map((v) => ({
              variant_id: v.variant_id,
              name: v.name || undefined,
              sku: v.sku || undefined,
              prices: pricesPayload(v),
            })),
          },
        });
      } else {
        await api("/v1/catalog/products", {
          method: "POST",
          orgId,
          body: {
            name,
            description: description || null,
            base_unit: baseUnit,
            is_taxable: isTaxable,
            variants: variants.map((v) => ({
              sku: v.sku || undefined,
              name: v.name || undefined,
              barcodes: v.barcode ? [{ barcode: v.barcode }] : [],
              prices: pricesPayload(v),
            })),
          },
        });
      }
      onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo guardar el artículo");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <form onSubmit={handleSubmit} className="mt-8 w-full max-w-2xl rounded-xl bg-white dark:bg-slate-800 shadow-lg">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
            {editing ? "Editar artículo" : "Nuevo artículo"}
          </h2>
        </div>
        <div className="space-y-4 px-6 py-5">
          <div className="grid grid-cols-3 gap-4">
            <Field label="Nombre">
              <Input required value={name} onChange={(event) => setName(event.target.value)} />
            </Field>
            <Field label="Unidad base">
              <Select value={baseUnit} onChange={(event) => setBaseUnit(event.target.value)}>
                <option value="unit">Unidad</option>
                <option value="kg">Kilogramo</option>
                <option value="g">Gramo</option>
                <option value="l">Litro</option>
                <option value="ml">Mililitro</option>
                <option value="box">Caja</option>
                <option value="pair">Par</option>
                <option value="pack">Paquete</option>
              </Select>
            </Field>
            <Field label="Descripción">
              <Input value={description} onChange={(event) => setDescription(event.target.value)} />
            </Field>
          </div>

          <label className="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200">
            <input
              type="checkbox"
              checked={isTaxable}
              onChange={(event) => setIsTaxable(event.target.checked)}
              className="h-4 w-4"
            />
            Este producto aplica impuesto (IVA)
          </label>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold text-slate-700 dark:text-slate-200">Modelos</h3>
              {!editing && (
                <Button
                  type="button"
                  variant="secondary"
                  onClick={() =>
                    setVariants((current) => [
                      ...current,
                      { sku: "", name: "", barcode: "", prices: [{ price_list_code: "retail", amount: "" }] },
                    ])
                  }
                >
                  Agregar modelo
                </Button>
              )}
            </div>

            {variants.map((variant, vi) => (
              <div key={vi} className="space-y-3 rounded-lg border border-slate-200 dark:border-slate-700 p-4">
                <div className="grid grid-cols-3 gap-3">
                  <Field label="SKU">
                    <Input value={variant.sku} onChange={(event) => updateVariant(vi, { sku: event.target.value })} />
                  </Field>
                  <Field label="Nombre del modelo (ej. Azul / M)">
                    <Input value={variant.name} onChange={(event) => updateVariant(vi, { name: event.target.value })} />
                  </Field>
                  {!editing && (
                    <Field label="Código de barras">
                      <Input value={variant.barcode} onChange={(event) => updateVariant(vi, { barcode: event.target.value })} />
                    </Field>
                  )}
                </div>

                <div className="grid grid-cols-3 gap-3">
                  {variant.prices.map((price, pi) => (
                    <Field key={pi} label={price.price_list_code === "retail" ? "Precio detal (USD)" : "Precio mayor (USD)"}>
                      <Input
                        type="number"
                        step="0.01"
                        min="0"
                        value={price.amount}
                        onChange={(event) => updatePrice(vi, pi, { amount: event.target.value })}
                      />
                    </Field>
                  ))}
                </div>

                {!editing && variants.length > 1 && (
                  <Button
                    type="button"
                    variant="danger"
                    onClick={() => setVariants((current) => current.filter((_, i) => i !== vi))}
                  >
                    Eliminar modelo
                  </Button>
                )}
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