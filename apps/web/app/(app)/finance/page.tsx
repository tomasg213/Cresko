"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";

import { Button, Card, CardHeader, EmptyState, ErrorState, Field, Input, LoadingState, Select, Table } from "@/components/ui";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type { ArReceivable, Balance, Invoice, Party } from "@/lib/types";
import { formatMoney } from "@/lib/utils";

type SupplierInvoice = { id: string; number: string; total: string; currency: string; status: string };

export default function FinancePage() {
  const { orgId } = useOrg();
  const [tab, setTab] = useState<"ar" | "ap">("ar");

  const arReceivables = useQuery({
    queryKey: ["ar-receivables", orgId],
    queryFn: () => api<ArReceivable[]>(`/v1/ar/receivables`, { orgId }),
    enabled: !!orgId,
  });
  const apBalances = useQuery({
    queryKey: ["ap-balances", orgId],
    queryFn: () => api<Balance[]>(`/v1/ap/balances`, { orgId }),
    enabled: !!orgId,
  });

  const balances = tab === "ar" ? arReceivables : apBalances;

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">Finanzas</h1>

      <div className="flex gap-2">
        {(["ar", "ap"] as const).map((option) => (
          <button
            key={option}
            onClick={() => setTab(option)}
            className={`rounded-lg px-4 py-2 text-sm font-medium ${
              tab === option ? "bg-primary text-white" : "bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-200"
            }`}
          >
            {option === "ar" ? "Por cobrar (clientes)" : "Por pagar (proveedores)"}
          </button>
        ))}
      </div>

      <Card>
        <CardHeader title={tab === "ar" ? "Cuentas por cobrar" : "Cuentas por pagar"} />
        {balances.isLoading ? (
          <LoadingState />
        ) : balances.isError ? (
          <ErrorState message={balances.error.message} onRetry={() => balances.refetch()} />
        ) : balances.data?.length === 0 ? (
          <EmptyState message="Sin saldos pendientes." />
        ) : tab === "ar" ? (
          <Table headers={["Factura", "Cliente", "Moneda", "Saldo"]}>
            {((balances.data ?? []) as ArReceivable[]).map((receivable) => (
              <tr key={receivable.invoice_id}>
                <td className="px-5 py-3 font-medium text-primary">{receivable.invoice_number}</td>
                <td className="px-5 py-3">{receivable.party_name ?? receivable.party_id}</td>
                <td className="px-5 py-3">{receivable.currency}</td>
                <td className="px-5 py-3 font-semibold">
                  {formatMoney(receivable.balance, receivable.currency)}
                </td>
              </tr>
            ))}
          </Table>
        ) : (
          <Table headers={["Proveedor", "Moneda", "Saldo"]}>
            {((balances.data ?? []) as Balance[]).map((balance, index) => (
              <tr key={`${balance.party_id}-${balance.currency}-${index}`}>
                <td className="px-5 py-3 font-medium">{balance.party_name ?? balance.party_id}</td>
                <td className="px-5 py-3">{balance.currency}</td>
                <td className="px-5 py-3 font-semibold">
                  {formatMoney(balance.balance, balance.currency)}
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      <PaymentForm tab={tab} />
    </div>
  );
}

function PaymentForm({ tab }: { tab: "ar" | "ap" }) {
  const { orgId } = useOrg();
  const [invoiceId, setInvoiceId] = useState("");
  const [amount, setAmount] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const invoices = useQuery({
    queryKey: ["invoices", orgId],
    queryFn: () => api<Invoice[]>(`/v1/pos/invoices`, { orgId }),
    enabled: !!orgId && tab === "ar",
  });
  const supplierInvoices = useQuery({
    queryKey: ["supplier-invoices", orgId],
    queryFn: () => api<SupplierInvoice[]>(`/v1/ap/invoices`, { orgId }),
    enabled: !!orgId && tab === "ap",
  });

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    setMessage(null);
    try {
      if (tab === "ar") {
        await api("/v1/ar/payments", {
          method: "POST",
          orgId,
          body: { invoice_id: invoiceId, amount: Number(amount), currency: "USD", method: "cash" },
        });
      } else {
        await api("/v1/ap/payments", {
          method: "POST",
          orgId,
          body: {
            supplier_invoice_id: invoiceId,
            amount: Number(amount),
            currency: "USD",
            method: "cash",
          },
        });
      }
      setMessage("Pago registrado.");
      setAmount("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo registrar el pago");
    }
  }

  return (
    <Card>
      <CardHeader title={tab === "ar" ? "Registrar cobro" : "Registrar pago a proveedor"} />
      <form onSubmit={handleSubmit} className="grid grid-cols-1 gap-4 px-5 py-4 sm:grid-cols-3">
        <Field label={tab === "ar" ? "Factura de venta" : "Factura de proveedor"}>
          <Select value={invoiceId} onChange={(event) => setInvoiceId(event.target.value)} required>
            <option value="">Seleccionar...</option>
            {(tab === "ar" ? invoices.data : supplierInvoices.data)?.map((doc) => (
              <option key={doc.id} value={doc.id}>
                {doc.number}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Monto (USD)">
          <Input type="number" step="0.01" min="0" value={amount} onChange={(event) => setAmount(event.target.value)} required />
        </Field>
        {error && <p className="text-sm text-red-600 sm:col-span-3">{error}</p>}
        {message && <p className="text-sm text-green-600 sm:col-span-3">{message}</p>}
        <div className="sm:col-span-3">
          <Button type="submit">{tab === "ar" ? "Registrar cobro" : "Registrar pago"}</Button>
        </div>
      </form>
    </Card>
  );
}