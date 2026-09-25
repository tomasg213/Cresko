"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { BadgeDollarSign, Plus, Trash2 } from "lucide-react";
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
import type { Order, Party, Product } from "@/lib/types";
import { formatMoney, formatQty } from "@/lib/utils";

const STATUS_LABEL: Record<Order["status"], string> = {
  pending: "Pendiente",
  partial: "Abonado",
  paid: "Pagado",
  cancelled: "Cancelado",
};

export default function OrdersPage() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const { confirm, notify } = useFeedback();
  const [open, setOpen] = useState(false);
  const [payingOrder, setPayingOrder] = useState<Order | null>(null);

  const orders = useQuery({
    queryKey: ["orders", orgId],
    queryFn: () => api<Order[]>(`/v1/orders`, { orgId }),
    enabled: !!orgId,
  });

  async function invalidate() {
    queryClient.invalidateQueries({ queryKey: ["orders", orgId] });
  }

  async function handleCancel(order: Order) {
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

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
          Pedidos
        </h1>
        <Button onClick={() => setOpen(true)}>
          <Plus className="h-4 w-4" />
          Añadir producto bajo pedido
        </Button>
      </div>

      <Card>
        <CardHeader title="Pedidos de clientes" />
        {orders.isLoading ? (
          <LoadingState />
        ) : orders.isError ? (
          <ErrorState
            message={orders.error.message}
            onRetry={() => orders.refetch()}
          />
        ) : orders.data?.length === 0 ? (
          <EmptyState message="Sin pedidos registrados. Usa «Añadir producto bajo pedido» para crear el primero." />
        ) : (
          <Table
            headers={[
              "Nº",
              "Cliente",
              "Producto",
              "Cant",
              "Total",
              "Pagado",
              "Deuda",
              "Estado",
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
                  <td className="px-5 py-3">
                    <div>{order.variant?.name ?? order.variant_id}</div>
                    <div className="text-xs text-slate-500 dark:text-slate-400">
                      {order.variant?.sku ?? ""}
                    </div>
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
                    <div className="flex justify-end gap-1">
                      {order.status !== "paid" &&
                        order.status !== "cancelled" && (
                          <Button
                            variant="secondary"
                            className="px-3 py-1 text-xs"
                            onClick={() => setPayingOrder(order)}
                          >
                            <BadgeDollarSign className="h-4 w-4" />
                            Cobrar
                          </Button>
                        )}
                      {order.status !== "cancelled" && (
                        <Button
                          variant="ghost"
                          className="px-2 py-1 text-red-600"
                          onClick={() => handleCancel(order)}
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

      {open && (
        <OrderModal
          onClose={() => setOpen(false)}
          onSaved={() => {
            setOpen(false);
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

function OrderModal({
  onClose,
  onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const { orgId } = useOrg();
  const { notify } = useFeedback();
  const [partyId, setPartyId] = useState("");
  const [variantId, setVariantId] = useState("");
  const [qty, setQty] = useState("1");
  const [unitCost, setUnitCost] = useState("");
  const [unitPrice, setUnitPrice] = useState("");
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
  const products = useQuery({
    queryKey: ["catalog", orgId],
    queryFn: () => api<Product[]>(`/v1/catalog/products`, { orgId }),
    enabled: !!orgId,
  });

  function selectVariant(variantId: string) {
    setVariantId(variantId);
    const variant = products.data
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
      await api(`/v1/orders`, {
        method: "POST",
        orgId,
        body: {
          party_id: partyId,
          variant_id: variantId,
          qty: Number(qty),
          unit_cost: Number(unitCost || 0),
          unit_price: Number(unitPrice),
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
    <Modal title="Añadir producto bajo pedido" onClose={onClose}>
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
        <Field label="Producto bajo pedido">
          <Select
            value={variantId}
            onChange={(event) => selectVariant(event.target.value)}
            required
          >
            <option value="">Seleccionar producto...</option>
            {products.data?.map((product) =>
              product.product_variants.map((variant) => (
                <option key={variant.id} value={variant.id}>
                  {product.name} — {variant.sku}
                </option>
              )),
            )}
          </Select>
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Cantidad">
            <Input
              type="number"
              min="0"
              step="0.001"
              value={qty}
              onChange={(event) => setQty(event.target.value)}
              required
            />
          </Field>
          <Field label="Costo del pedido (USD)">
            <Input
              type="number"
              min="0"
              step="0.01"
              value={unitCost}
              onChange={(event) => setUnitCost(event.target.value)}
            />
          </Field>
        </div>
        <div className="grid grid-cols-2 gap-4">
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
        </div>
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
