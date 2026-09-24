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
import { useFeedback } from "@/components/feedback";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type {
  ApPayment,
  ApReceivable,
  ArPayment,
  ArReceivable,
} from "@/lib/types";
import { formatMoney } from "@/lib/utils";

type Receivable = ArReceivable | ApReceivable;

type PartyGroup = {
  party_id: string;
  party_name: string;
  currency: string;
  total: string;
  invoices: Receivable[];
};

const METHODS = ["cash", "card", "transfer"] as const;

function groupByParty(rows: Receivable[]): PartyGroup[] {
  const map = new Map<string, PartyGroup>();
  for (const row of rows) {
    if (Number(row.balance) <= 0) continue;
    const key = `${row.party_id}::${row.currency}`;
    const group = map.get(key) ?? {
      party_id: row.party_id,
      party_name: row.party_name ?? row.party_id,
      currency: row.currency,
      total: "0",
      invoices: [],
    };
    group.invoices.push(row);
    group.total = String(Number(group.total) + Number(row.balance));
    map.set(key, group);
  }
  return [...map.values()].sort((a, b) =>
    a.party_name.localeCompare(b.party_name),
  );
}

export default function FinancePage() {
  const { orgId } = useOrg();
  const [tab, setTab] = useState<"ar" | "ap">("ar");

  const arReceivables = useQuery({
    queryKey: ["ar-receivables", orgId],
    queryFn: () => api<ArReceivable[]>(`/v1/ar/receivables`, { orgId }),
    enabled: !!orgId && tab === "ar",
  });
  const apReceivables = useQuery({
    queryKey: ["ap-receivables", orgId],
    queryFn: () => api<ApReceivable[]>(`/v1/ap/receivables`, { orgId }),
    enabled: !!orgId && tab === "ap",
  });

  const receivables = tab === "ar" ? arReceivables : apReceivables;
  const groups = groupByParty(receivables.data ?? []);

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
        Finanzas
      </h1>

      <div className="flex gap-2">
        {(["ar", "ap"] as const).map((option) => (
          <button
            key={option}
            onClick={() => setTab(option)}
            className={`rounded-lg px-4 py-2 text-sm font-medium ${
              tab === option
                ? "bg-primary text-white"
                : "bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-200"
            }`}
          >
            {option === "ar"
              ? "Por cobrar (clientes)"
              : "Por pagar (proveedores)"}
          </button>
        ))}
      </div>

      {receivables.isLoading ? (
        <LoadingState />
      ) : receivables.isError ? (
        <ErrorState
          message={receivables.error.message}
          onRetry={() => receivables.refetch()}
        />
      ) : groups.length === 0 ? (
        <EmptyState message="Sin saldos pendientes." />
      ) : (
        groups.map((group) => (
          <PartyCard
            key={`${group.party_id}-${group.currency}`}
            group={group}
            tab={tab}
          />
        ))
      )}

      <PaymentsList tab={tab} />
    </div>
  );
}

function PartyCard({ group, tab }: { group: PartyGroup; tab: "ar" | "ap" }) {
  const { orgId } = useOrg();
  const { notify } = useFeedback();
  const queryClient = useQueryClient();
  const [generalAmount, setGeneralAmount] = useState("");
  const [generalMethod, setGeneralMethod] =
    useState<(typeof METHODS)[number]>("cash");
  const [generalError, setGeneralError] = useState<string | null>(null);
  const [generalMessage, setGeneralMessage] = useState<string | null>(null);
  const [abonoFor, setAbonoFor] = useState<Receivable | null>(null);

  async function invalidate() {
    queryClient.invalidateQueries({
      queryKey: [tab === "ar" ? "ar-receivables" : "ap-receivables", orgId],
    });
    queryClient.invalidateQueries({
      queryKey: [tab === "ar" ? "ar-payments" : "ap-payments", orgId],
    });
  }

  async function submitGeneral(event: React.FormEvent) {
    event.preventDefault();
    setGeneralError(null);
    setGeneralMessage(null);
    const amount = Number(generalAmount);
    if (!amount || amount <= 0) {
      setGeneralError("Ingresa un monto válido.");
      return;
    }
    try {
      const base = tab === "ar" ? "ar" : "ap";
      await api(`/v1/${base}/payments/general`, {
        method: "POST",
        orgId,
        body: {
          party_id: group.party_id,
          amount,
          currency: "USD",
          method: generalMethod,
        },
      });
      setGeneralMessage("Pago general aplicado.");
      setGeneralAmount("");
      await invalidate();
    } catch (err) {
      setGeneralError(
        err instanceof Error ? err.message : "No se pudo aplicar el pago",
      );
    }
  }

  async function payInvoice(invoice: Receivable) {
    setGeneralError(null);
    setGeneralMessage(null);
    try {
      const base = tab === "ar" ? "ar" : "ap";
      const body =
        base === "ar"
          ? {
              invoice_id: (invoice as ArReceivable).invoice_id,
              amount: Number(invoice.balance),
              currency: "USD",
              method: "cash",
            }
          : {
              supplier_invoice_id: (invoice as ApReceivable)
                .supplier_invoice_id,
              amount: Number(invoice.balance),
              currency: "USD",
              method: "cash",
            };
      await api(`/v1/${base}/payments`, { method: "POST", orgId, body });
      setGeneralMessage("Pago registrado.");
      await invalidate();
    } catch (err) {
      setGeneralError(
        err instanceof Error ? err.message : "No se pudo registrar el pago",
      );
    }
  }

  async function submitAbono(invoice: Receivable, amount: number) {
    setGeneralError(null);
    setGeneralMessage(null);
    try {
      const base = tab === "ar" ? "ar" : "ap";
      const body =
        base === "ar"
          ? {
              invoice_id: (invoice as ArReceivable).invoice_id,
              amount,
              currency: "USD",
              method: "cash",
            }
          : {
              supplier_invoice_id: (invoice as ApReceivable)
                .supplier_invoice_id,
              amount,
              currency: "USD",
              method: "cash",
            };
      await api(`/v1/${base}/payments`, { method: "POST", orgId, body });
      setAbonoFor(null);
      setGeneralMessage("Abono registrado.");
      await invalidate();
    } catch (err) {
      notify(
        err instanceof Error ? err.message : "No se pudo registrar el abono",
      );
    }
  }

  return (
    <Card>
      <CardHeader
        title={`${group.party_name} — ${formatMoney(group.total, group.currency)}`}
      />
      <div className="px-5 py-4">
        <form
          onSubmit={submitGeneral}
          className="mb-4 grid grid-cols-1 gap-4 sm:grid-cols-4"
        >
          <div className="sm:col-span-1">
            <Field label="Pago general (USD)">
              <Input
                type="number"
                step="0.01"
                min="0"
                value={generalAmount}
                onChange={(event) => setGeneralAmount(event.target.value)}
                placeholder="Monto"
              />
            </Field>
          </div>
          <div className="sm:col-span-1">
            <Field label="Método">
              <Select
                value={generalMethod}
                onChange={(event) =>
                  setGeneralMethod(
                    event.target.value as (typeof METHODS)[number],
                  )
                }
              >
                {METHODS.map((method) => (
                  <option key={method} value={method}>
                    {method}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
          <div className="sm:col-span-2 flex items-end">
            <Button type="submit">Aplicar pago general</Button>
          </div>
          {generalError && (
            <p className="text-sm text-red-600 sm:col-span-4">{generalError}</p>
          )}
          {generalMessage && (
            <p className="text-sm text-green-600 sm:col-span-4">
              {generalMessage}
            </p>
          )}
        </form>

        <Table headers={["Factura", "Saldo", "Acciones"]}>
          {group.invoices.map((invoice) => (
            <tr
              key={
                "invoice_id" in invoice
                  ? invoice.invoice_id
                  : invoice.supplier_invoice_id
              }
            >
              <td className="px-5 py-3 font-medium text-primary">
                {invoice.invoice_number}
              </td>
              <td className="px-5 py-3 font-semibold">
                {formatMoney(invoice.balance, invoice.currency)}
              </td>
              <td className="px-5 py-3">
                <div className="flex flex-wrap gap-2">
                  <Button
                    variant="secondary"
                    className="px-3 py-1 text-xs"
                    onClick={() => {
                      setAbonoFor(abonoFor === invoice ? null : invoice);
                      setGeneralError(null);
                      setGeneralMessage(null);
                    }}
                  >
                    Abonar
                  </Button>
                  <Button
                    className="px-3 py-1 text-xs"
                    onClick={() => payInvoice(invoice)}
                  >
                    Pagar
                  </Button>
                </div>
                {abonoFor === invoice && (
                  <AbonoForm
                    invoice={invoice}
                    onCancel={() => setAbonoFor(null)}
                    onSubmit={(amount) => submitAbono(invoice, amount)}
                  />
                )}
              </td>
            </tr>
          ))}
        </Table>
      </div>
    </Card>
  );
}

function AbonoForm({
  invoice,
  onCancel,
  onSubmit,
}: {
  invoice: Receivable;
  onCancel: () => void;
  onSubmit: (amount: number) => void;
}) {
  const { notify } = useFeedback();
  const [amount, setAmount] = useState("");
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        const value = Number(amount);
        if (!value || value <= 0) {
          notify("Ingresa un monto válido.");
          return;
        }
        if (value > Number(invoice.balance)) {
          notify("El monto no puede ser mayor que la deuda de la factura.");
          return;
        }
        onSubmit(value);
      }}
      className="mt-2 flex flex-wrap items-center gap-2"
    >
      <Input
        type="number"
        step="0.01"
        min="0"
        value={amount}
        onChange={(event) => setAmount(event.target.value)}
        placeholder="Monto (USD)"
        className="w-40"
        autoFocus
      />
      <Button type="submit" className="px-3 py-1 text-xs">
        Registrar abono
      </Button>
      <Button
        type="button"
        variant="ghost"
        className="px-3 py-1 text-xs"
        onClick={onCancel}
      >
        Cancelar
      </Button>
    </form>
  );
}

function PaymentsList({ tab }: { tab: "ar" | "ap" }) {
  const { orgId } = useOrg();
  const { confirm, notify } = useFeedback();
  const queryClient = useQueryClient();

  const arPayments = useQuery({
    queryKey: ["ar-payments", orgId],
    queryFn: () => api<ArPayment[]>(`/v1/ar/payments`, { orgId }),
    enabled: !!orgId && tab === "ar",
  });
  const apPayments = useQuery({
    queryKey: ["ap-payments", orgId],
    queryFn: () => api<ApPayment[]>(`/v1/ap/payments`, { orgId }),
    enabled: !!orgId && tab === "ap",
  });

  const payments = tab === "ar" ? arPayments : apPayments;

  async function handleVoid(id: string) {
    if (
      !(await confirm(
        "¿Anular este pago? Se registrará una reversión en el saldo.",
      ))
    )
      return;
    try {
      await api(`/v1/${tab === "ar" ? "ar" : "ap"}/payments/${id}/void`, {
        method: "POST",
        orgId,
      });
      queryClient.invalidateQueries({
        queryKey: [tab === "ar" ? "ar-payments" : "ap-payments", orgId],
      });
      queryClient.invalidateQueries({
        queryKey: [tab === "ar" ? "ar-receivables" : "ap-receivables", orgId],
      });
    } catch (err) {
      notify(err instanceof Error ? err.message : "No se pudo anular el pago");
    }
  }

  return (
    <Card>
      <CardHeader
        title={tab === "ar" ? "Cobros registrados" : "Pagos registrados"}
      />
      {payments.isLoading ? (
        <LoadingState />
      ) : payments.isError ? (
        <ErrorState
          message={payments.error.message}
          onRetry={() => payments.refetch()}
        />
      ) : payments.data?.length === 0 ? (
        <EmptyState message="Sin pagos registrados." />
      ) : (
        <Table
          headers={[
            "Factura",
            "Contraparte",
            "Monto",
            "Moneda",
            "Fecha",
            "Estado",
            "",
          ]}
        >
          {payments.data?.map((payment) => {
            const amount = Number(payment.amount);
            const isAp = tab === "ap";
            const shown = isAp ? -amount : amount;
            return (
              <tr key={payment.id}>
                <td className="px-5 py-3 font-medium">
                  {isAp
                    ? (payment as ApPayment).invoice_number
                    : (payment as ArPayment).invoice_number}
                </td>
                <td className="px-5 py-3">
                  {isAp
                    ? (payment as ApPayment).supplier_name
                    : (payment as ArPayment).party_name}
                </td>
                <td className="px-5 py-3 font-semibold">
                  {formatMoney(String(shown), payment.currency)}
                </td>
                <td className="px-5 py-3">{payment.currency}</td>
                <td className="px-5 py-3 text-slate-600 dark:text-slate-400">
                  {new Date(payment.created_at).toLocaleDateString()}
                </td>
                <td className="px-5 py-3">
                  {"status" in payment && payment.status === "void" ? (
                    <span className="text-red-600">Anulado</span>
                  ) : (
                    <span className="text-green-600">Vigente</span>
                  )}
                </td>
                <td className="px-5 py-3">
                  {!("status" in payment) || payment.status === "posted" ? (
                    <div className="flex justify-end">
                      <Button
                        variant="danger"
                        className="px-3 py-1 text-xs"
                        onClick={() => handleVoid(payment.id)}
                      >
                        Anular
                      </Button>
                    </div>
                  ) : null}
                </td>
              </tr>
            );
          })}
        </Table>
      )}
    </Card>
  );
}
