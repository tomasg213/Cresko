"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Camera, Plus, Search, Trash2 } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";

import { Button, Card, ErrorState, Field, Input, LoadingState, Select } from "@/components/ui";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import { findVariantByBarcode, loadCatalog, saveCatalog } from "@/lib/catalogCache";
import { PrintDialog } from "@/components/sale-document";
import type { FxRate, Invoice, Party, Product, StockLevel, Variant, WarehouseRef } from "@/lib/types";
import { formatMoney } from "@/lib/utils";

type CartLine = {
  variant: Variant;
  qty: number;
  unitPrice: number;
  taxable: boolean;
};

type CatalogEntry = {
  product: Product;
  variant: Variant;
};

export default function PosPage() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const inputRef = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState("");
  const [highlightedIndex, setHighlightedIndex] = useState(0);
  const [cart, setCart] = useState<CartLine[]>([]);
  const [priceList, setPriceList] = useState<"retail" | "wholesale">("retail");
  const [warehouseId, setWarehouseId] = useState("");
  const [customerMode, setCustomerMode] = useState<"current" | "registered">("current");
  const [selectedCustomerId, setSelectedCustomerId] = useState("");
  const [customerModalOpen, setCustomerModalOpen] = useState(false);
  const [paid, setPaid] = useState("");
  const [paymentMethod, setPaymentMethod] = useState<"cash" | "credit">("cash");
  const [result, setResult] = useState<Invoice | null>(null);
  const [printInvoice, setPrintInvoice] = useState<Invoice | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const products = useQuery({
    queryKey: ["catalog", orgId],
    queryFn: async (): Promise<Product[]> => {
      const rows = await api<Product[]>(`/v1/catalog/products`, { orgId });
      if (orgId) void saveCatalog(orgId, rows);
      return rows;
    },
    enabled: !!orgId,
    staleTime: 60_000,
  });

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

  const customers = useQuery({
    queryKey: ["parties", orgId, "customer"],
    queryFn: () => api<Party[]>(`/v1/parties?kind=customer`, { orgId }),
    enabled: !!orgId,
  });

  const rate = useQuery({
    queryKey: ["fx-rate", orgId],
    queryFn: () => api<FxRate>(`/v1/fx/rate`, { orgId }),
    enabled: !!orgId,
    retry: false,
  });

  const exchangeRate = rate.data ? Number(rate.data.rate) : null;

  useEffect(() => {
    if (orgId) {
      void loadCatalog(orgId).then((cached) => {
        if (cached && cached.length > 0 && !queryClient.getQueryData(["catalog", orgId])) {
          queryClient.setQueryData(["catalog", orgId], cached);
        }
      });
    }
  }, [orgId, queryClient]);

  useEffect(() => {
    const list = warehouses.data ?? [];
    if (!warehouseId && list.length > 0) setWarehouseId(list[0]!.id);
  }, [warehouses.data, warehouseId]);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  function addVariant(variant: Variant, taxable: boolean) {
    setCart((current) => {
      const existing = current.find((line) => line.variant.id === variant.id);
      const unitPrice = getPrice(variant);
      if (existing) {
        return current.map((line) =>
          line.variant.id === variant.id ? { ...line, qty: line.qty + 1 } : line,
        );
      }
      if (unitPrice === null) return current;
      return [...current, { variant, qty: 1, unitPrice, taxable }];
    });
  }

  function getPrice(variant: Variant): number | null {
    const price = variant.variant_prices.find(
      (p) => p.currency === "USD" && (p.price_list?.code ?? "retail") === priceList,
    );
    return price ? Number(price.amount) : null;
  }

  function normalize(value: string) {
    return value
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "");
  }

  const trimmedQuery = query.trim();
  const normalizedQuery = normalize(trimmedQuery);

  const results = useMemo(() => {
    if (!normalizedQuery) return [];
    const catalog = products.data ?? [];
    const matches: CatalogEntry[] = [];
    for (const product of catalog) {
      for (const variant of product.product_variants) {
        const haystack = [
          product.name,
          variant.name,
          product.description ?? "",
          variant.sku,
          ...variant.barcodes.map((b) => b.barcode),
        ]
          .map(normalize)
          .join(" ");
        if (haystack.includes(normalizedQuery)) {
          matches.push({ product, variant });
        }
        if (matches.length >= 8) break;
      }
      if (matches.length >= 8) break;
    }
    return matches;
  }, [normalizedQuery, products.data]);

  function findExactVariant(): CatalogEntry | null {
    if (!trimmedQuery) return null;
    const catalog = products.data ?? [];
    const byBarcode = findVariantByBarcode(catalog, trimmedQuery);
    if (byBarcode) {
      const product = catalog.find((p) => p.product_variants.some((v) => v.id === byBarcode.id));
      return product ? { product, variant: byBarcode } : null;
    }
    const q = trimmedQuery.toLowerCase();
    for (const product of catalog) {
      const variant = product.product_variants.find((v) => v.sku.toLowerCase() === q);
      if (variant) return { product, variant };
    }
    return null;
  }

  function clearQuery() {
    setQuery("");
    setHighlightedIndex(0);
  }

  function handleAdd(entry: CatalogEntry) {
    const price = getPrice(entry.variant);
    if (price === null) {
      setError(
        `"${entry.variant.name}" no tiene precio en ${priceList === "retail" ? "detal" : "mayor"} (USD).`,
      );
      return;
    }
    setError(null);
    addVariant(entry.variant, entry.product.is_taxable);
    clearQuery();
    inputRef.current?.focus();
  }

  function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!trimmedQuery) return;

    const exact = findExactVariant();
    if (exact) {
      handleAdd(exact);
      return;
    }
    if (results.length > 0) {
      const index = Math.min(highlightedIndex, results.length - 1);
      handleAdd(results[index]);
      return;
    }
    setError(`No se encontró "${trimmedQuery}". Agrégalo al catálogo o revisa el nombre.`);
  }

  function handleKeyDown(event: React.KeyboardEvent) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      if (results.length > 0) {
        setHighlightedIndex((current) => (current + 1) % results.length);
      }
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      if (results.length > 0) {
        setHighlightedIndex((current) => (current - 1 + results.length) % results.length);
      }
    }
  }

  function updateQty(index: number, qty: number) {
    setCart((current) => current.map((line, i) => (i === index ? { ...line, qty } : line)));
  }

  function removeLine(index: number) {
    setCart((current) => current.filter((_, i) => i !== index));
  }

  const subtotalUsd = cart.reduce((sum, line) => sum + line.unitPrice * line.qty, 0);
  const subtotal = exchangeRate ? subtotalUsd * exchangeRate : 0;
  const tax = cart.reduce((sum, line) => {
    if (!line.taxable) return sum;
    return sum + line.unitPrice * line.qty * (exchangeRate ?? 0) * 0.16;
  }, 0);
  const total = subtotal + tax;

  async function handleCheckout() {
    if (cart.length === 0 || exchangeRate === null) return;
    if (cart.some((line) => line.qty <= 0)) {
      setError("Revisa las cantidades del carrito: deben ser mayores a cero.");
      return;
    }
    if (paymentMethod === "credit" && !selectedCustomerId) {
      setError("Para vender a crédito debes seleccionar un cliente registrado o crear uno nuevo.");
      return;
    }
    setSubmitting(true);
    setError(null);
    setResult(null);
    try {
      const invoice = await api<Invoice>(`/v1/pos/checkout`, {
        method: "POST",
        orgId,
        body: {
          warehouse_id: warehouseId,
          price_list_code: priceList,
          tax_rate: 16,
          lines: cart.map((line) => ({ variant_id: line.variant.id, qty: line.qty })),
          payment_method: paymentMethod,
          paid_amount: paymentMethod === "credit" ? (paid ? Number(paid) : 0) : total,
          party_id: selectedCustomerId || undefined,
        },
      });
      setResult(invoice);
      const full = await api<Invoice>(`/v1/pos/invoices/${invoice.id}`, { orgId });
      setPrintInvoice(full);
      setCart([]);
      setPaid("");
      setSelectedCustomerId("");
      setCustomerMode("current");
      queryClient.invalidateQueries({ queryKey: ["stock", orgId] });
      queryClient.invalidateQueries({ queryKey: ["ar-balances", orgId] });
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo completar la venta");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">Punto de venta</h1>
        <div className="flex items-center gap-2 text-sm text-slate-500 dark:text-slate-400">
          <Camera className="h-4 w-4" />
          Escanea un código o busca por nombre
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          <Card className="p-4">
            <form onSubmit={handleSubmit} className="relative">
              <div className="relative">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                <Input
                  ref={inputRef}
                  value={query}
                  onChange={(event) => {
                    setQuery(event.target.value);
                    setHighlightedIndex(0);
                  }}
                  onKeyDown={handleKeyDown}
                  placeholder="Código de barras, SKU o nombre del producto..."
                  autoFocus
                  className="w-full pl-9"
                />
              </div>

              {normalizedQuery && results.length > 0 && (
                <div className="absolute z-20 mt-1 w-full overflow-hidden rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 shadow-lg">
                  {results.map((entry, index) => {
                    const price = getPrice(entry.variant);
                    return (
                      <button
                        key={entry.variant.id}
                        type="button"
                        onClick={() => handleAdd(entry)}
                        onMouseEnter={() => setHighlightedIndex(index)}
                        className={`flex w-full items-center justify-between gap-3 border-b border-slate-100 px-4 py-2.5 text-left ${
                          index === highlightedIndex ? "bg-primary/10" : "hover:bg-slate-50 dark:hover:bg-slate-800 dark:bg-slate-800"
                        }`}
                      >
                        <div className="min-w-0">
                          <div className="truncate text-sm font-medium text-slate-900 dark:text-slate-100">
                            {entry.variant.name}
                          </div>
                          <div className="truncate text-xs text-slate-500 dark:text-slate-400">
                            {entry.product.name} · {entry.variant.sku}
                          </div>
                        </div>
                        <div className="text-right text-sm font-semibold text-slate-700 dark:text-slate-200">
                          {price !== null ? (
                            formatMoney(String(price), "USD")
                          ) : (
                            <span className="text-amber-600">Sin precio</span>
                          )}
                        </div>
                      </button>
                    );
                  })}
                </div>
              )}
              {normalizedQuery && results.length === 0 && (
                <div className="mt-1 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 px-4 py-2 text-sm text-slate-500 dark:text-slate-400">
                  Sin resultados para "{query}"
                </div>
              )}
            </form>

            {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
          </Card>

          <Card>
            <div className="border-b border-slate-200 dark:border-slate-700 px-5 py-3 text-sm font-semibold text-slate-900 dark:text-slate-100">
              Carrito
            </div>
            {products.isLoading ? (
              <LoadingState />
            ) : cart.length === 0 ? (
              <div className="px-5 py-10 text-center text-sm text-slate-500 dark:text-slate-400">
                El carrito está vacío
              </div>
            ) : (
              <div className="divide-y divide-slate-100 dark:divide-slate-800">
                {cart.map((line, index) => (
                  <div key={line.variant.id} className="flex items-center gap-4 px-5 py-3">
                    <div className="flex-1">
                      <div className="font-medium text-slate-900 dark:text-slate-100">{line.variant.name}</div>
                      <div className="text-xs text-slate-500 dark:text-slate-400">{line.variant.sku}</div>
                    </div>
                    <div className="flex items-center gap-2">
                      <button
                        className="rounded border border-slate-300 dark:border-slate-600 px-2 py-1 text-sm"
                        onClick={() => updateQty(index, Math.max(0, line.qty - 1))}
                      >
                        −
                      </button>
                      <Input
                        type="number"
                        min="0"
                        step="0.001"
                        value={line.qty}
                        onChange={(event) => updateQty(index, event.target.value === "" ? 0 : Number(event.target.value))}
                        className="w-20 px-2 text-center"
                      />
                      <button
                        className="rounded border border-slate-300 dark:border-slate-600 px-2 py-1 text-sm"
                        onClick={() => updateQty(index, line.qty + 1)}
                      >
                        +
                      </button>
                    </div>
                    <div className="w-24 text-right text-sm font-semibold">
                      {formatMoney(String(line.unitPrice * line.qty), "USD")}
                    </div>
                    <button className="text-slate-400 hover:text-red-600" onClick={() => removeLine(index)}>
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>

        <div className="space-y-4">
          <Card className="p-4">
            <div className="mb-3">
              <Select
                value={priceList}
                onChange={(event) => setPriceList(event.target.value as "retail" | "wholesale")}
                className="w-full"
              >
                <option value="retail">Detal (USD)</option>
                <option value="wholesale">Mayor (USD)</option>
              </Select>
            </div>
            <Select value={warehouseId} onChange={(event) => setWarehouseId(event.target.value)} className="mb-3 w-full">
              <option value="">Almacén...</option>
              {(warehouses.data ?? []).map((warehouse) => (
                <option key={warehouse.id} value={warehouse.id}>
                  {warehouse.name}
                </option>
              ))}
            </Select>
            <div className="mb-3">
              <div className="mb-2 grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => {
                    setCustomerMode("current");
                    setSelectedCustomerId("");
                  }}
                  className={`rounded-lg px-3 py-2 text-sm font-medium ${
                    customerMode === "current"
                      ? "bg-slate-800 text-white dark:bg-slate-200 dark:text-slate-900"
                      : "border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800 dark:bg-slate-800"
                  }`}
                >
                  Cliente corriente
                </button>
                <button
                  type="button"
                  onClick={() => setCustomerMode("registered")}
                  className={`rounded-lg px-3 py-2 text-sm font-medium ${
                    customerMode === "registered"
                      ? "bg-slate-800 text-white dark:bg-slate-200 dark:text-slate-900"
                      : "border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800 dark:bg-slate-800"
                  }`}
                >
                  Clientes registrados
                </button>
              </div>
              {customerMode === "registered" ? (
                <Select
                  value={selectedCustomerId}
                  onChange={(event) => setSelectedCustomerId(event.target.value)}
                  className="w-full"
                >
                  <option value="">Seleccionar cliente...</option>
                  {customers.data?.map((customer) => (
                    <option key={customer.id} value={customer.id}>
                      {customer.name}
                    </option>
                  ))}
                </Select>
              ) : null}
              <Button
                type="button"
                variant="secondary"
                className="mt-2 w-full"
                onClick={() => setCustomerModalOpen(true)}
              >
                <Plus className="h-4 w-4" />
                Nuevo cliente
              </Button>
            </div>
          </Card>

          <Card className="p-4">
            <div className="mb-3 grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setPaymentMethod("cash")}
                className={`rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                  paymentMethod === "cash"
                    ? "bg-primary text-white"
                    : "border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800 dark:bg-slate-800"
                }`}
              >
                Contado
              </button>
              <button
                type="button"
                onClick={() => setPaymentMethod("credit")}
                className={`rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                  paymentMethod === "credit"
                    ? "bg-amber-50 dark:bg-amber-9500 text-white"
                    : "border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800 dark:bg-slate-800"
                }`}
              >
                Crédito (fiado)
              </button>
            </div>
            {paymentMethod === "credit" && (
              <div className="mb-3 text-xs text-amber-700">
                Se registrará una cuenta por cobrar por el saldo. Debes indicar el cliente.
              </div>
            )}
            {exchangeRate === null ? (
              <div className="rounded-lg bg-amber-50 dark:bg-amber-950 p-3 text-sm text-amber-700">
                No hay tasa BCV configurada. Regístrala en Configuración para poder cobrar.
              </div>
            ) : (
              <div className="mb-2 text-xs text-slate-500 dark:text-slate-400">
                Tasa BCV: {formatMoney(exchangeRate.toFixed(4), "VES")} por USD
              </div>
            )}
            <div className="space-y-1 text-sm">
              <div className="flex justify-between">
                <span className="text-slate-500 dark:text-slate-400">Subtotal</span>
                <span className="font-medium">{formatMoney(String(subtotal), "VES")}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500 dark:text-slate-400">IVA (16%)</span>
                <span className="font-medium">{formatMoney(String(tax), "VES")}</span>
              </div>
              <div className="flex justify-between border-t border-slate-200 dark:border-slate-700 pt-2 text-base font-semibold">
                <span>Total (Bs.)</span>
                <span>{formatMoney(String(total), "VES")}</span>
              </div>
            </div>
            {paymentMethod === "credit" ? (
              <Input
                type="number"
                step="0.01"
                value={paid}
                onChange={(event) => setPaid(event.target.value)}
                placeholder="Abono inicial (Bs., opcional)"
                className="mt-3 w-full"
              />
            ) : (
              <div className="mt-3 rounded-lg bg-slate-50 dark:bg-slate-800 p-3 text-xs text-slate-600 dark:text-slate-400">
                Contado: se registra el pago del total ({formatMoney(String(total), "VES")})
              </div>
            )}
            <Button
              className="mt-3 w-full"
              onClick={handleCheckout}
              disabled={submitting || cart.length === 0 || exchangeRate === null}
            >
              {submitting ? "Procesando..." : "Cobrar"}
            </Button>
            {result && (
              <div className="mt-3 rounded-lg bg-green-50 dark:bg-green-950 p-3 text-sm text-green-700">
                Venta completada. Factura {result.number}
              </div>
            )}
          </Card>
        </div>
      </div>

      {customerModalOpen && (
        <NewCustomerModal
          onClose={() => setCustomerModalOpen(false)}
          onCreated={(customer) => {
            setCustomerModalOpen(false);
            setCustomerMode("registered");
            setSelectedCustomerId(customer.id);
            customers.refetch();
          }}
        />
      )}

      {printInvoice && (
        <PrintDialog
          invoice={printInvoice}
          onClose={() => {
            setPrintInvoice(null);
            setResult(null);
          }}
        />
      )}
    </div>
  );
}

function NewCustomerModal({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: (customer: Party) => void;
}) {
  const { orgId } = useOrg();
  const [name, setName] = useState("");
  const [documentType, setDocumentType] = useState("rif");
  const [documentId, setDocumentId] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const customer = await api<Party>("/v1/pos/customers", {
        method: "POST",
        orgId,
        body: {
          name,
          document_type: documentType,
          document_id: documentId || null,
          phone: phone || null,
          email: email || null,
        },
      });
      onCreated(customer);
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo registrar el cliente");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <form onSubmit={handleSubmit} className="mt-16 w-full max-w-md rounded-xl bg-white dark:bg-slate-800 shadow-lg">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">Nuevo cliente</h2>
        </div>
        <div className="space-y-4 px-6 py-5">
          <Field label="Nombre">
            <Input required value={name} onChange={(event) => setName(event.target.value)} />
          </Field>
          <div className="grid grid-cols-2 gap-4">
            <Field label="Tipo de documento">
              <Select value={documentType} onChange={(event) => setDocumentType(event.target.value)}>
                <option value="rif">RIF</option>
                <option value="ci">Cédula</option>
                <option value="passport">Pasaporte</option>
                <option value="other">Otro</option>
              </Select>
            </Field>
            <Field label="Número">
              <Input value={documentId} onChange={(event) => setDocumentId(event.target.value)} />
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Field label="Teléfono">
              <Input value={phone} onChange={(event) => setPhone(event.target.value)} />
            </Field>
            <Field label="Correo">
              <Input type="email" value={email} onChange={(event) => setEmail(event.target.value)} />
            </Field>
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
        </div>
        <div className="flex justify-end gap-3 border-t border-slate-200 dark:border-slate-700 px-6 py-4">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancelar
          </Button>
          <Button type="submit" disabled={submitting}>
            {submitting ? "Guardando..." : "Registrar cliente"}
          </Button>
        </div>
      </form>
    </div>
  );
}