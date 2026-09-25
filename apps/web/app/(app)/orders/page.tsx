"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  BadgeDollarSign,
  PackageCheck,
  Pencil,
  Plus,
  Trash2,
} from "lucide-react";
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
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type { Order, Party, Product, SpecialOrderProduct } from "@/lib/types";
import { formatMoney, formatQty } from "@/lib/utils";

const STATUS_LABEL: Record<Order["status"], string> = {
  pending: "Por cobrar",
  partial: "Abonado",
  paid: "Pagado",
  cancelled: "Cancelado",
};

const DELIVERY_LABEL: Record<Order["delivery_status"], string> = {
  pending: "Por entregar",
  delivered: "Entregado",
};

export default function OrdersPage() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const { confirm, notify } = useFeedback();
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<SpecialOrderProduct | null>(null);
  const [selected, setSelected] = useState<SpecialOrderProduct | null>(null);
  const [orderModal, setOrderModal] = useState(false);
  const [payingOrder, setPayingOrder] = useState<Order | null>(null);

  const products = useQuery({
    queryKey: ["special-order-products", orgId],
    queryFn: () => api<SpecialOrderProduct[]>(`/v1/orders/products`, { orgId }),
    enabled: !!orgId,
  });

  const orders = useQuery({
    queryKey: ["orders", orgId, selected?.id],
    queryFn: () =>
      api<Order[]>(`/v1/orders?product_id=${selected!.id}`, { orgId }),
    enabled: !!orgId && !!selected,
  });

  async function invalidate() {
    queryClient.invalidateQueries({
      queryKey: ["special-order-products", orgId],
    });
    queryClient.invalidateQueries({ queryKey: ["orders", orgId] });
  }

  async function handleDelete(product: SpecialOrderProduct) {
    if (!(await confirm(`¿Eliminar "${product.variant?.name ?? ""}"?`))) return;
    try {
      await api(`/v1/orders/products/${product.id}`, {
        method: "PATCH",
        orgId,
        body: { is_active: false },
      });
      await invalidate();
    } catch (err) {
      notify(
        err instanceof Error ? err.message : "No se pudo eliminar el producto",
      );
    }
  }

  async function handleCancelOrder(order: Order) {
    if (!(await confirm(`¿Cancelar el pedido ${order.number}?`))) return;
    try {
      await api(`/v1/orders/${order.id}/cancel`, { method: "POST", orgId });
      await invalidate();
    } catch (err) {
      notify(
        err instanceof Error ? err.message : "No se pudo cancelar el pedido",
      );
    }
  }

  async function handleDeliverOrder(order: Order) {
    if (
      !(await confirm(
        `¿Marcar el pedido ${order.number} como entregado?${
          Number(order.total) - Number(order.paid_amount) > 0
            ? " El saldo pendiente pasará a cuenta por cobrar."
            : " Al estar pagado, el pedido se eliminará."
        }`,
      ))
    )
      return;
    try {
      await api(`/v1/orders/${order.id}/deliver`, { method: "POST", orgId });
      await invalidate();
    } catch (err) {
      notify(
        err instanceof Error
          ? err.message
          : "No se pudo marcar el pedido como entregado",
      );
    }
  }

  if (selected) {
    return (
      <div className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-3">
            <Button variant="secondary" onClick={() => setSelected(null)}>
              <ArrowLeft className="h-4 w-4" />
              Volver
            </Button>
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
                {selected.variant?.name ?? "Producto bajo pedido"}
              </h1>
              <div className="text-sm text-slate-500 dark:text-slate-400">
                {selected.variant?.sku ? `${selected.variant.sku} · ` : ""}
                {formatMoney(selected.unit_price, selected.currency)} precio de
                venta
              </div>
            </div>
          </div>
          <Button onClick={() => setOrderModal(true)}>
            <Plus className="h-4 w-4" />
            Nuevo pedido de cliente
          </Button>
        </div>

        <Card>
          <CardHeader
            title={`Pedidos de clientes — ${selected.variant?.name ?? ""}`}
          />
          {orders.isLoading ? (
            <LoadingState />
          ) : orders.isError ? (
            <ErrorState
              message={orders.error.message}
              onRetry={() => orders.refetch()}
            />
          ) : orders.data?.length === 0 ? (
            <EmptyState message="Este producto aún no tiene pedidos de clientes. Usa «Nuevo pedido de cliente» para registrar el primero." />
          ) : (
            <Table
              headers={[
                "Nº",
                "Cliente",
                "Cant",
                "Total",
                "Pagado",
                "Deuda",
                "Estado",
                "Entrega",
                "",
              ]}
            >
              {orders.data?.map((order) => {
                const balance = Number(order.total) - Number(order.paid_amount);
                return (
                  <tr key={order.id}>
                    <td className="px-5 py-3 font-medium text-primary">
                      {order.number}
                    </td>
                    <td className="px-5 py-3">
                      {order.party?.name ?? order.party_id}
                    </td>
                    <td className="px-5 py-3">{formatQty(order.qty)}</td>
                    <td className="px-5 py-3 font-semibold">
                      {formatMoney(order.total, order.currency)}
                    </td>
                    <td className="px-5 py-3 text-green-700 dark:text-green-400">
                      {formatMoney(order.paid_amount, order.currency)}
                    </td>
                    <td className="px-5 py-3">
                      {balance > 0 ? (
                        <span className="font-semibold text-red-600">
                          {formatMoney(String(balance), order.currency)}
                        </span>
                      ) : (
                        <span className="text-slate-400">—</span>
                      )}
                    </td>
                    <td className="px-5 py-3">
                      <span
                        className={
                          order.status === "paid"
                            ? "text-green-600"
                            : order.status === "partial"
                              ? "text-amber-600"
                              : order.status === "cancelled"
                                ? "text-slate-400 line-through"
                                : "text-slate-600"
                        }
                      >
                        {STATUS_LABEL[order.status]}
                      </span>
                    </td>
                    <td className="px-5 py-3">
                      <span
                        className={
                          order.delivery_status === "delivered"
                            ? "text-green-600"
                            : "text-slate-600"
                        }
                      >
                        {DELIVERY_LABEL[order.delivery_status]}
                      </span>
                    </td>
                    <td className="px-5 py-3">
                      <div className="flex justify-end gap-1">
                        {order.status !== "cancelled" &&
                          order.delivery_status === "pending" && (
                            <Button
                              variant="secondary"
                              className="px-3 py-1 text-xs"
                              onClick={() => handleDeliverOrder(order)}
                            >
                              <PackageCheck className="h-4 w-4" />
                              Entregar
                            </Button>
                          )}
                        {order.status !== "paid" &&
                          order.status !== "cancelled" &&
                          order.delivery_status === "pending" && (
                            <Button
                              variant="secondary"
                              className="px-3 py-1 text-xs"
                              onClick={() => setPayingOrder(order)}
                            >
                              <BadgeDollarSign className="h-4 w-4" />
                              Cobrar
                            </Button>
                          )}
                        {order.status !== "cancelled" &&
                          order.delivery_status === "pending" && (
                            <Button
                              variant="ghost"
                              className="px-2 py-1 text-red-600"
                              onClick={() => handleCancelOrder(order)}
                              aria-label="Cancelar pedido"
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </Table>
          )}
        </Card>

        {orderModal && (
          <OrderModal
            product={selected}
            onClose={() => setOrderModal(false)}
            onSaved={() => {
              setOrderModal(false);
              void invalidate();
            }}
          />
        )}
        {payingOrder && (
          <PayOrderModal
            order={payingOrder}
            onClose={() => setPayingOrder(null)}
            onSaved={() => {
              setPayingOrder(null);
              void invalidate();
            }}
          />
        )}
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
          Pedidos
        </h1>
        <Button
          onClick={() => {
            setEditing(null);
            setOpen(true);
          }}
        >
          <Plus className="h-4 w-4" />
          Añadir producto bajo pedido
        </Button>
      </div>

      <p className="text-sm text-slate-500 dark:text-slate-400">
        Configura aquí los productos del catálogo que se venden bajo pedido. Al
        entrar en uno, registrarás los pedidos de cada cliente.
      </p>

      <Card>
        <CardHeader title="Productos bajo pedido" />
        {products.isLoading ? (
          <LoadingState />
        ) : products.isError ? (
          <ErrorState
            message={products.error.message}
            onRetry={() => products.refetch()}
          />
        ) : products.data?.length === 0 ? (
          <EmptyState message="Sin productos bajo pedido. Usa «Añadir producto bajo pedido» para crear el primero." />
        ) : (
          <Table headers={["Producto", "Precio", "Estado", ""]}>
            {products.data
              ?.filter((p) => p.is_active)
              .map((product) => (
                <tr key={product.id}>
                  <td className="px-5 py-3">
                    <button
                      className="font-medium text-primary hover:underline"
                      onClick={() => setSelected(product)}
                    >
                      {product.variant?.name ?? "Producto"}
                    </button>
                    {product.variant?.sku && (
                      <div className="text-xs text-slate-500 dark:text-slate-400">
                        {product.variant.sku}
                      </div>
                    )}
                  </td>
                  <td className="px-5 py-3 font-semibold">
                    {formatMoney(product.unit_price, product.currency)}
                  </td>
                  <td className="px-5 py-3">
                    <span className="text-green-600">Activo</span>
                  </td>
                  <td className="px-5 py-3">
                    <div className="flex justify-end gap-1">
                      <Button
                        variant="ghost"
                        className="px-2 py-1"
                        onClick={() => {
                          setEditing(product);
                          setOpen(true);
                        }}
                        aria-label="Editar"
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        className="px-2 py-1 text-red-600"
                        onClick={() => handleDelete(product)}
                        aria-label="Eliminar"
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

      {open && (
        <ProductModal
          product={editing}
          onClose={() => setOpen(false)}
          onSaved={() => {
            setOpen(false);
            setEditing(null);
            void invalidate();
          }}
        />
      )}
    </div>
  );
}

function ProductModal({
  product,
  onClose,
  onSaved,
}: {
  product: SpecialOrderProduct | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { orgId } = useOrg();
  const [variantId, setVariantId] = useState(product?.variant_id ?? "");
  const [unitPrice, setUnitPrice] = useState(product?.unit_price ?? "");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const catalog = useQuery({
    queryKey: ["catalog", orgId],
    queryFn: () => api<Product[]>(`/v1/catalog/products`, { orgId }),
    enabled: !!orgId,
  });

  function selectVariant(variantId: string) {
    setVariantId(variantId);
    const variant = catalog.data
      ?.flatMap((p) => p.product_variants)
      .find((v) => v.id === variantId);
    if (variant) {
      const price = variant.variant_prices.find(
        (p) =>
          p.currency === "USD" && (p.price_list?.code ?? "retail") === "retail",
      );
      if (price) setUnitPrice(String(price.amount));
    }
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const body = {
        unit_price: Number(unitPrice || 0),
      };
      if (product) {
        await api(`/v1/orders/products/${product.id}`, {
          method: "PATCH",
          orgId,
          body,
        });
      } else {
        await api(`/v1/orders/products`, {
          method: "POST",
          orgId,
          body: { variant_id: variantId, ...body },
        });
      }
      onSaved();
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "No se pudo guardar el producto",
      );
      setSubmitting(false);
    }
  }

  return (
    <Modal
      title={
        product ? "Editar producto bajo pedido" : "Añadir producto bajo pedido"
      }
      onClose={onClose}
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        <Field label="Producto del catálogo">
          <Select
            value={variantId}
            onChange={(event) => selectVariant(event.target.value)}
            required
            disabled={!!product}
          >
            <option value="">Seleccionar producto del catálogo...</option>
            {catalog.data?.map((prod) =>
              prod.product_variants.map((variant) => (
                <option key={variant.id} value={variant.id}>
                  {prod.name} — {variant.sku}
                </option>
              )),
            )}
          </Select>
        </Field>
        <Field label="Precio de venta (USD)">
          <Input
            type="number"
            min="0"
            step="0.01"
            value={unitPrice}
            onChange={(event) => setUnitPrice(event.target.value)}
            required
          />
        </Field>
        <p className="text-xs text-slate-500 dark:text-slate-400">
          El producto debe estar registrado en el catálogo para poder venderlo
          bajo pedido.
        </p>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <div className="flex justify-end gap-3 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancelar
          </Button>
          <Button type="submit" disabled={submitting}>
            {submitting ? "Guardando..." : "Guardar"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}

function OrderModal({
  product,
  onClose,
  onSaved,
}: {
  product: SpecialOrderProduct;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { orgId } = useOrg();
  const { notify } = useFeedback();
  const [partyId, setPartyId] = useState("");
  const [qty, setQty] = useState("1");
  const [unitPrice, setUnitPrice] = useState(product.unit_price);
  const [paidAmount, setPaidAmount] = useState("");
  const [paymentMethod, setPaymentMethod] = useState<
    "cash" | "card" | "transfer"
  >("cash");
  const [expectedAt, setExpectedAt] = useState("");
  const [notes, setNotes] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const customers = useQuery({
    queryKey: ["parties", orgId, "customer"],
    queryFn: () => api<Party[]>(`/v1/parties?kind=customer`, { orgId }),
    enabled: !!orgId,
  });

  const qtyValue = Number(qty) || 0;
  const priceValue = Number(unitPrice) || 0;
  const total = qtyValue * priceValue;

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await api(`/v1/orders`, {
        method: "POST",
        orgId,
        body: {
          product_id: product.id,
          party_id: partyId,
          qty: qtyValue,
          unit_price: priceValue,
          currency: "USD",
          exchange_rate: 1,
          paid_amount: Number(paidAmount || 0),
          payment_method: paymentMethod,
          expected_at: expectedAt || null,
          notes: notes || null,
        },
      });
      onSaved();
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "No se pudo registrar el pedido",
      );
      setSubmitting(false);
    }
  }

  return (
    <Modal
      title={`Nuevo pedido — ${product.variant?.name ?? ""}`}
      onClose={onClose}
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        <Field label="Cliente">
          <Select
            value={partyId}
            onChange={(event) => setPartyId(event.target.value)}
            required
          >
            <option value="">Seleccionar cliente...</option>
            {customers.data?.map((customer) => (
              <option key={customer.id} value={customer.id}>
                {customer.name}
              </option>
            ))}
          </Select>
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Cantidad">
            <Input
              type="number"
              min="0"
              step="0.01"
              value={qty}
              onChange={(event) => setQty(event.target.value)}
              required
            />
          </Field>
          <Field label="Precio de venta (USD)">
            <Input
              type="number"
              min="0"
              step="0.01"
              value={unitPrice}
              onChange={(event) => setUnitPrice(event.target.value)}
              required
            />
          </Field>
        </div>
        <div className="rounded-lg bg-slate-50 px-4 py-3 dark:bg-slate-800">
          <div className="flex justify-between text-sm">
            <span className="text-slate-500 dark:text-slate-400">
              Costo total del pedido
            </span>
            <span className="font-semibold text-slate-900 dark:text-slate-100">
              {formatMoney(String(total), "USD")}
            </span>
          </div>
          <p className="mt-1 text-xs text-slate-500 dark:text-slate-400">
            Cantidad × precio de venta
          </p>
        </div>
        <Field label="Monto pagado (USD)">
          <Input
            type="number"
            min="0"
            step="0.01"
            value={paidAmount}
            onChange={(event) => setPaidAmount(event.target.value)}
            placeholder="0"
          />
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Método de pago">
            <Select
              value={paymentMethod}
              onChange={(event) =>
                setPaymentMethod(
                  event.target.value as "cash" | "card" | "transfer",
                )
              }
            >
              <option value="cash">Efectivo</option>
              <option value="card">Tarjeta</option>
              <option value="transfer">Transferencia</option>
            </Select>
          </Field>
          <Field label="Fecha estimada de entrega">
            <Input
              type="date"
              value={expectedAt}
              onChange={(event) => setExpectedAt(event.target.value)}
            />
          </Field>
        </div>
        <Field label="Notas">
          <Input
            value={notes}
            onChange={(event) => setNotes(event.target.value)}
          />
        </Field>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <div className="flex justify-end gap-3 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancelar
          </Button>
          <Button type="submit" disabled={submitting}>
            {submitting ? "Guardando..." : "Registrar pedido"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}

function PayOrderModal({
  order,
  onClose,
  onSaved,
}: {
  order: Order;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { orgId } = useOrg();
  const { notify } = useFeedback();
  const balance = Number(order.total) - Number(order.paid_amount);
  const [amount, setAmount] = useState(String(balance));
  const [method, setMethod] = useState<"cash" | "card" | "transfer">("cash");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    const value = Number(amount);
    if (!value || value <= 0) {
      notify("Ingresa un monto válido.");
      setSubmitting(false);
      return;
    }
    if (value > balance) {
      notify("El monto no puede ser mayor que toda la deuda");
      setSubmitting(false);
      return;
    }
    try {
      await api(`/v1/orders/${order.id}/pay`, {
        method: "POST",
        orgId,
        body: { amount: value, method },
      });
      onSaved();
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "No se pudo registrar el pago",
      );
      setSubmitting(false);
    }
  }

  return (
    <Modal title={`Cobrar ${order.number}`} onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="text-sm text-slate-600 dark:text-slate-300">
          Deuda pendiente:{" "}
          <span className="font-semibold text-red-600">
            {formatMoney(String(balance), order.currency)}
          </span>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Monto a cobrar">
            <Input
              type="number"
              min="0"
              step="0.01"
              value={amount}
              onChange={(event) => setAmount(event.target.value)}
              required
            />
          </Field>
          <Field label="Método">
            <Select
              value={method}
              onChange={(event) =>
                setMethod(event.target.value as "cash" | "card" | "transfer")
              }
            >
              <option value="cash">Efectivo</option>
              <option value="card">Tarjeta</option>
              <option value="transfer">Transferencia</option>
            </Select>
          </Field>
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <div className="flex justify-end gap-3 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancelar
          </Button>
          <Button type="submit" disabled={submitting}>
            {submitting ? "Cobrando..." : "Registrar cobro"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
