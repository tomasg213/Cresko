"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Camera, Plus, Search, Trash2 } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";

import {
  Button,
  Card,
  ErrorState,
  Field,
  Input,
  LoadingState,
  Select,
} from "@/components/ui";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import {
  findVariantByBarcode,
  loadCatalog,
  saveCatalog,
} from "@/lib/catalogCache";
import { PrintDialog } from "@/components/sale-document";
import { PhoneField } from "@/components/phone-field";
import { formatDocument } from "@/lib/documents";
import { formatPhone } from "@/lib/phones";
import BarcodeScannerModal from "@/components/barcode-scanner";
import type {
  CashClose,
  FxRate,
  Invoice,
  Party,
  Product,
  StockLevel,
  Variant,
  WarehouseRef,
} from "@/lib/types";
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
  const [customerMode, setCustomerMode] = useState<"current" | "registered">(
    "current",
  );
  const [selectedCustomerId, setSelectedCustomerId] = useState("");
  const [customerModalOpen, setCustomerModalOpen] = useState(false);
  const [cashAmount, setCashAmount] = useState("");
  const [cardAmount, setCardAmount] = useState("");
  const [biopagoAmount, setBiopagoAmount] = useState("");
  const [creditMode, setCreditMode] = useState(false);
  const [result, setResult] = useState<Invoice | null>(null);
  const [printInvoice, setPrintInvoice] = useState<Invoice | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [scannerOpen, setScannerOpen] = useState(false);

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

  const cashClose = useQuery({
    queryKey: ["cash-closes", orgId],
    queryFn: () => api<CashClose | null>(`/v1/cash-closes/current`, { orgId }),
    enabled: !!orgId,
    retry: false,
  });

  const exchangeRate = rate.data ? Number(rate.data.rate) : null;

  useEffect(() => {
    if (orgId) {
      void loadCatalog(orgId).then((cached) => {
        if (
          cached &&
          cached.length > 0 &&
          !queryClient.getQueryData(["catalog", orgId])
        ) {
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
          line.variant.id === variant.id
            ? { ...line, qty: line.qty + 1 }
            : line,
        );
      }
      if (unitPrice === null) return current;
      return [...current, { variant, qty: 1, unitPrice, taxable }];
    });
  }

  function getPrice(variant: Variant): number | null {
    const price = variant.variant_prices.find(
      (p) =>
        p.currency === "USD" && (p.price_list?.code ?? "retail") === priceList,
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

  function findExactByCode(code: string): CatalogEntry | null {
    if (!code) return null;
    const catalog = products.data ?? [];
    const byBarcode = findVariantByBarcode(catalog, code);
    if (byBarcode) {
      const product = catalog.find((p) =>
        p.product_variants.some((v) => v.id === byBarcode.id),
      );
      return product ? { product, variant: byBarcode } : null;
    }
    const q = code.toLowerCase();
    for (const product of catalog) {
      const variant = product.product_variants.find(
        (v) => v.sku.toLowerCase() === q,
      );
      if (variant) return { product, variant };
    }
    return null;
  }

  function findExactVariant(): CatalogEntry | null {
    return findExactByCode(trimmedQuery);
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

  function handleScannedCode(code: string) {
    setScannerOpen(false);
    const entry = findExactByCode(code);
    if (entry) {
      handleAdd(entry);
      return;
    }
    setError(
      `No se encontró el código "${code}". Agrégalo al catálogo o revisa el código.`,
    );
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
    setError(
      `No se encontró "${trimmedQuery}". Agrégalo al catálogo o revisa el nombre.`,
    );
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
        setHighlightedIndex(
          (current) => (current - 1 + results.length) % results.length,
        );
      }
    }
  }

  function updateQty(index: number, qty: number) {
    setCart((current) =>
      current.map((line, i) => (i === index ? { ...line, qty } : line)),
    );
  }

  function removeLine(index: number) {
    setCart((current) => current.filter((_, i) => i !== index));
  }

  const subtotalUsd = cart.reduce(
    (sum, line) => sum + line.unitPrice * line.qty,
    0,
  );
  const subtotal = exchangeRate ? subtotalUsd * exchangeRate : 0;
  const taxUsd = cart.reduce((sum, line) => {
    if (!line.taxable) return sum;
    return sum + line.unitPrice * line.qty * 0.16;
  }, 0);
  const totalUsd = subtotalUsd + taxUsd;
  const tax = taxUsd * (exchangeRate ?? 0);
  const total = subtotal + tax;

  async function handleCheckout() {
    if (cart.length === 0 || exchangeRate === null) return;
    if (cart.some((line) => line.qty <= 0)) {
      setError("Revisa las cantidades del carrito: deben ser mayores a cero.");
      return;
    }

    const cash = Number(cashAmount) || 0;
    const card = Number(cardAmount) || 0;
    const biopago = Number(biopagoAmount) || 0;
    const paidVes = cash + card + biopago;
    const hasCredit = paidVes < total;

    if (paidVes > total + 0.01) {
      setError("El pago no puede ser mayor que el total de la venta.");
      return;
    }
    if (hasCredit && !creditMode) {
      setError(
        "El monto pagado no cubre el total de la venta. Activa «Permitir fiado» para dejar saldo a crédito.",
      );
      return;
    }
    if (hasCredit && !selectedCustomerId) {
      setError(
        "Para dejar saldo a crédito (fiado) debes seleccionar un cliente registrado o crear uno nuevo.",
      );
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
          lines: cart.map((line) => ({
            variant_id: line.variant.id,
            qty: line.qty,
          })),
          payment_method: "credit",
          paid_amount: paidVes,
          payments: [
            { method: "cash", amount: cash },
            { method: "card", amount: card },
            { method: "biopago", amount: biopago },
          ],
          party_id: selectedCustomerId || undefined,
        },
      });
      setResult(invoice);
      const full = await api<Invoice>(`/v1/pos/invoices/${invoice.id}`, {
        orgId,
      });
      setPrintInvoice(full);
      setCart([]);
      setCashAmount("");
      setCardAmount("");
      setBiopagoAmount("");
      setSelectedCustomerId("");
      setCustomerMode("current");
      setCreditMode(false);
      queryClient.invalidateQueries({ queryKey: ["stock", orgId] });
      queryClient.invalidateQueries({ queryKey: ["ar-balances", orgId] });
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "No se pudo completar la venta",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
          Punto de venta
        </h1>
        <div className="flex items-center gap-2 text-sm text-slate-500 dark:text-slate-400">
          <Camera className="h-4 w-4" />
          Escanea un código o busca por nombre
        </div>
      </div>

      {cashClose.isError ? (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-900 dark:bg-red-950">
          <span className="font-semibold">
            Debes realizar el cuadre de caja del día anterior antes de vender.
          </span>{" "}
          Dirígete al módulo{" "}
          <a href="/cash-closes" className="font-medium underline">
            Cuadres de caja
          </a>{" "}
          para cerrarlo.
        </div>
      ) : !cashClose.data ? (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-900 dark:bg-amber-950">
          No hay un cuadre de caja abierto para hoy. Se abrirá automáticamente
          al realizar la primera venta.
        </div>
      ) : (
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-600 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300">
          <span>
            Cuadre de caja:{" "}
            <span className="font-semibold text-slate-900 dark:text-slate-100">
              {cashClose.data.number}
            </span>
          </span>
          <a
            href="/cash-closes"
            className="font-medium text-primary hover:underline"
          >
            Ver cuadres de caja
          </a>
        </div>
      )}

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
                  className="w-full pl-9 pr-11"
                />
                <button
                  type="button"
                  onClick={() => setScannerOpen(true)}
                  aria-label="Escanear con la cámara"
                  title="Escanear con la cámara"
                  className="absolute right-2 top-1/2 -translate-y-1/2 rounded-lg p-1.5 text-slate-400 transition-colors hover:bg-slate-100 hover:text-primary dark:hover:bg-slate-700"
                >
                  <Camera className="h-5 w-5" />
                </button>
              </div>

              {normalizedQuery && results.length > 0 && (
                <div className="absolute z-20 mt-1 w-full overflow-hidden rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 shadow-lg">
                  {results.map((entry, index) => {
                    const price = getPrice(entry.variant);
                    const priceVes =
                      price !== null && exchangeRate !== null
                        ? price * exchangeRate
                        : null;
                    return (
                      <button
                        key={entry.variant.id}
                        type="button"
                        onClick={() => handleAdd(entry)}
                        onMouseEnter={() => setHighlightedIndex(index)}
                        className={`flex w-full items-center justify-between gap-3 border-b border-slate-100 px-4 py-2.5 text-left ${
                          index === highlightedIndex
                            ? "bg-primary/10"
                            : "hover:bg-slate-50 dark:hover:bg-slate-800 dark:bg-slate-800"
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
                        <div className="text-right">
                          {price !== null ? (
                            <>
                              <div className="text-sm font-semibold text-slate-700 dark:text-slate-200">
                                {formatMoney(String(price), "USD")}
                              </div>
                              {priceVes !== null && (
                                <div className="text-[11px] font-normal text-slate-500 dark:text-slate-400">
                                  {formatMoney(String(priceVes), "VES")}
                                </div>
                              )}
                            </>
                          ) : (
                            <span className="text-amber-600 text-sm">
                              Sin precio
                            </span>
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
                  <div
                    key={line.variant.id}
                    className="flex items-center gap-4 px-5 py-3"
                  >
                    <div className="flex-1">
                      <div className="font-medium text-slate-900 dark:text-slate-100">
                        {line.variant.name}
                      </div>
                      <div className="text-xs text-slate-500 dark:text-slate-400">
                        {line.variant.sku}
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <button
                        className="rounded border border-slate-300 dark:border-slate-600 px-2 py-1 text-sm"
                        onClick={() =>
                          updateQty(index, Math.max(0, line.qty - 1))
                        }
                      >
                        −
                      </button>
                      <Input
                        type="number"
                        min="0"
                        step="0.01"
                        value={line.qty}
                        onChange={(event) =>
                          updateQty(
                            index,
                            event.target.value === ""
                              ? 0
                              : Number(event.target.value),
                          )
                        }
                        className="w-20 px-2 text-center"
                      />
                      <button
                        className="rounded border border-slate-300 dark:border-slate-600 px-2 py-1 text-sm"
                        onClick={() => updateQty(index, line.qty + 1)}
                      >
                        +
                      </button>
                    </div>
                    <div className="w-24 text-right">
                      <div className="text-sm font-semibold">
                        {formatMoney(String(line.unitPrice * line.qty), "USD")}
                      </div>
                      {exchangeRate !== null && (
                        <div className="text-[11px] font-normal text-slate-500 dark:text-slate-400">
                          {formatMoney(
                            String(line.unitPrice * line.qty * exchangeRate),
                            "VES",
                          )}
                        </div>
                      )}
                    </div>
                    <button
                      className="text-slate-400 hover:text-red-600"
                      onClick={() => removeLine(index)}
                    >
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
                onChange={(event) =>
                  setPriceList(event.target.value as "retail" | "wholesale")
                }
                className="w-full"
              >
                <option value="retail">Detal (USD)</option>
                <option value="wholesale">Mayor (USD)</option>
              </Select>
            </div>
            <Select
              value={warehouseId}
              onChange={(event) => setWarehouseId(event.target.value)}
              className="mb-3 w-full"
            >
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
                  onChange={(event) =>
                    setSelectedCustomerId(event.target.value)
                  }
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
            <div className="mb-3 flex items-center justify-between">
              <div className="text-sm font-semibold text-slate-900 dark:text-slate-100">
                Pago
              </div>
              <button
                type="button"
                onClick={() => setCreditMode((value) => !value)}
                className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors ${
                  creditMode
                    ? "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200"
                    : "border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700"
                }`}
              >
                {creditMode ? "Permitir fiado" : "Permitir fiado"}
              </button>
            </div>

            {exchangeRate === null ? (
              <div className="rounded-lg bg-amber-50 dark:bg-amber-950 p-3 text-sm text-amber-700">
                No hay tasa BCV configurada. Regístrala en Configuración para
                poder cobrar.
              </div>
            ) : (
              <div className="mb-2 text-xs text-slate-500 dark:text-slate-400">
                Tasa BCV: {formatMoney(exchangeRate.toFixed(2), "VES")} por USD
              </div>
            )}

            <div className="mb-3 grid grid-cols-3 gap-2">
              <div>
                <Field label="Efectivo (Bs.)">
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    value={cashAmount}
                    onChange={(event) => setCashAmount(event.target.value)}
                    placeholder="0"
                  />
                </Field>
                <button
                  type="button"
                  onClick={() =>
                    setCashAmount(
                      String(
                        Math.max(
                          total -
                            ((Number(cardAmount) || 0) +
                              (Number(biopagoAmount) || 0)),
                          0,
                        ),
                      ),
                    )
                  }
                  className="mt-1 w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700"
                >
                  Saldo
                </button>
              </div>
              <div>
                <Field label="Tarjeta (Bs.)">
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    value={cardAmount}
                    onChange={(event) => setCardAmount(event.target.value)}
                    placeholder="0"
                  />
                </Field>
                <button
                  type="button"
                  onClick={() =>
                    setCardAmount(
                      String(
                        Math.max(
                          total -
                            ((Number(cashAmount) || 0) +
                              (Number(biopagoAmount) || 0)),
                          0,
                        ),
                      ),
                    )
                  }
                  className="mt-1 w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700"
                >
                  Saldo
                </button>
              </div>
              <div>
                <Field label="BioPago (Bs.)">
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    value={biopagoAmount}
                    onChange={(event) => setBiopagoAmount(event.target.value)}
                    placeholder="0"
                  />
                </Field>
                <button
                  type="button"
                  onClick={() =>
                    setBiopagoAmount(
                      String(
                        Math.max(
                          total -
                            ((Number(cashAmount) || 0) +
                              (Number(cardAmount) || 0)),
                          0,
                        ),
                      ),
                    )
                  }
                  className="mt-1 w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700"
                >
                  Saldo
                </button>
              </div>
            </div>

            {(() => {
              const cash = Number(cashAmount) || 0;
              const card = Number(cardAmount) || 0;
              const biopago = Number(biopagoAmount) || 0;
              const paid = cash + card + biopago;
              const balance = Math.max(total - paid, 0);
              return (
                <div className="mb-3 space-y-1 text-xs">
                  <div className="flex justify-between border-t border-slate-200 dark:border-slate-700 pt-2 text-sm font-semibold">
                    <span>Total de la factura (Bs.)</span>
                    <span>{formatMoney(String(total), "VES")}</span>
                  </div>
                  <div className="flex justify-between text-green-700 dark:text-green-400">
                    <span>Pagado (Bs.)</span>
                    <span>{formatMoney(String(paid), "VES")}</span>
                  </div>
                  {creditMode && (
                    <div className="flex justify-between font-medium text-amber-700">
                      <span>Fiado (crédito)</span>
                      <span>{formatMoney(String(balance), "VES")}</span>
                    </div>
                  )}
                </div>
              );
            })()}

            {creditMode && (
              <p className="mb-3 text-xs text-amber-700">
                El saldo no pagado quedará como cuenta por cobrar. Debes
                seleccionar el cliente.
              </p>
            )}

            <Button
              className="mt-2 w-full"
              onClick={handleCheckout}
              disabled={
                submitting || cart.length === 0 || exchangeRate === null
              }
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

      {scannerOpen && (
        <BarcodeScannerModal
          onDetected={handleScannedCode}
          onClose={() => {
            setScannerOpen(false);
            inputRef.current?.focus();
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
          document_id: formatDocument(documentType, documentId) || null,
          phone: phone ? formatPhone(phone) : null,
          email: email || null,
        },
      });
      onCreated(customer);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "No se pudo registrar el cliente",
      );
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <form
        onSubmit={handleSubmit}
        className="mt-16 w-full max-w-md rounded-xl bg-white dark:bg-slate-800 shadow-lg"
      >
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
            Nuevo cliente
          </h2>
        </div>
        <div className="space-y-4 px-6 py-5">
          <Field label="Nombre">
            <Input
              required
              value={name}
              onChange={(event) => setName(event.target.value)}
            />
          </Field>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label="Tipo de documento">
              <Select
                value={documentType}
                onChange={(event) => setDocumentType(event.target.value)}
              >
                <option value="rif">RIF</option>
                <option value="ci">Cédula</option>
                <option value="passport">Pasaporte</option>
                <option value="other">Otro</option>
              </Select>
            </Field>
            <Field label="Número">
              <Input
                value={documentId}
                onChange={(event) =>
                  setDocumentId(
                    formatDocument(documentType, event.target.value),
                  )
                }
                placeholder={
                  documentType === "ci"
                    ? "V-12.345.678"
                    : documentType === "rif"
                      ? "J-12345678-9"
                      : documentType === "passport"
                        ? "E-123456789"
                        : ""
                }
              />
            </Field>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <PhoneField value={phone} onChange={setPhone} />
            <Field label="Correo">
              <Input
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
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
