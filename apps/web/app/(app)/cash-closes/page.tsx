"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Calculator, CheckCircle2 } from "lucide-react";
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
import type { CashClose, CashCloseTransaction } from "@/lib/types";
import { formatMoney } from "@/lib/utils";

export default function CashClosesPage() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const { confirm, notify } = useFeedback();
  const [selected, setSelected] = useState<CashClose | null>(null);
  const [summary, setSummary] = useState<Record<string, string> | null>(null);

  const closes = useQuery({
    queryKey: ["cash-closes", orgId],
    queryFn: () => api<CashClose[]>(`/v1/cash-closes`, { orgId }),
    enabled: !!orgId,
  });

  const transactions = useQuery({
    queryKey: ["cash-close-transactions", orgId, selected?.id],
    queryFn: () =>
      api<CashCloseTransaction[]>(
        `/v1/cash-closes/${selected!.id}/transactions`,
        { orgId },
      ),
    enabled: !!orgId && !!selected,
  });

  async function invalidate() {
    queryClient.invalidateQueries({ queryKey: ["cash-closes", orgId] });
    queryClient.invalidateQueries({
      queryKey: ["cash-close-transactions", orgId],
    });
  }

  async function handleClose(cashClose: CashClose) {
    if (
      !(await confirm(
        `¿Cerrar el cuadre ${cashClose.number}? Se capturarán todas las facturas y pedidos del día.`,
      ))
    )
      return;
    try {
      const result = await api<Record<string, string>>(
        `/v1/cash-closes/${cashClose.id}/close`,
        { method: "POST", orgId },
      );
      setSummary(result);
      await invalidate();
    } catch (err) {
      notify(
        err instanceof Error ? err.message : "No se pudo cerrar el cuadre",
      );
    }
  }

  const openClose = closes.data?.find((c) => c.status === "open");

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
        Cuadres de caja
      </h1>

      {summary && (
        <Card className="border-green-200 dark:border-green-900">
          <div className="grid grid-cols-2 gap-3 px-5 py-4 sm:grid-cols-4">
            <SummaryItem
              label="Efectivo"
              value={formatMoney(summary.cash_usd, "USD")}
            />
            <SummaryItem
              label="Tarjeta"
              value={formatMoney(summary.card_usd, "USD")}
            />
            <SummaryItem
              label="BioPago"
              value={formatMoney(summary.biopago_usd, "USD")}
            />
            <SummaryItem
              label="Fiado (crédito)"
              value={formatMoney(summary.credit_usd, "USD")}
            />
          </div>
          <div className="flex items-center justify-between border-t border-slate-200 px-5 py-3 text-sm dark:border-slate-700">
            <span className="text-slate-600 dark:text-slate-300">
              Total ingresado:{" "}
              <span className="font-semibold text-slate-900 dark:text-slate-100">
                {formatMoney(summary.paid_usd, "USD")}
              </span>
            </span>
            <span className="text-slate-500 dark:text-slate-400">
              {summary.transactions} transacciones
            </span>
          </div>
        </Card>
      )}

      <Card>
        <CardHeader
          title="Cuadres"
          action={
            openClose ? (
              <Button onClick={() => handleClose(openClose)}>
                <CheckCircle2 className="h-4 w-4" />
                Cerrar cuadre {openClose.number}
              </Button>
            ) : undefined
          }
        />
        {closes.isLoading ? (
          <LoadingState />
        ) : closes.isError ? (
          <ErrorState
            message={closes.error.message}
            onRetry={() => closes.refetch()}
          />
        ) : closes.data?.length === 0 ? (
          <EmptyState message="Sin cuadres de caja. Se crea uno automáticamente con la primera venta del día." />
        ) : (
          <Table headers={["Nº", "Fecha", "Estado", "Acciones"]}>
            {closes.data?.map((cashClose) => (
              <tr key={cashClose.id}>
                <td className="px-5 py-3 font-medium text-primary">
                  {cashClose.number}
                </td>
                <td className="px-5 py-3">
                  {new Date(cashClose.opened_at).toLocaleDateString("es-VE")}
                </td>
                <td className="px-5 py-3">
                  {cashClose.status === "open" ? (
                    <span className="text-green-600">Abierto</span>
                  ) : (
                    <span className="text-slate-500">Cerrado</span>
                  )}
                </td>
                <td className="px-5 py-3">
                  <div className="flex justify-end gap-1">
                    <Button
                      variant="secondary"
                      className="px-3 py-1 text-xs"
                      onClick={() => {
                        setSelected(cashClose);
                        setSummary(null);
                      }}
                    >
                      <Calculator className="h-4 w-4" />
                      Ver detalle
                    </Button>
                    {cashClose.status === "open" && (
                      <Button
                        className="px-3 py-1 text-xs"
                        onClick={() => handleClose(cashClose)}
                      >
                        Cerrar
                      </Button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      {selected && (
        <Card>
          <CardHeader
            title={`Transacciones — ${selected.number}`}
            action={
              <Button
                variant="secondary"
                className="px-3 py-1 text-xs"
                onClick={() => setSelected(null)}
              >
                Cerrar detalle
              </Button>
            }
          />
          {transactions.isLoading ? (
            <LoadingState />
          ) : transactions.isError ? (
            <ErrorState
              message={transactions.error.message}
              onRetry={() => transactions.refetch()}
            />
          ) : transactions.data?.length === 0 ? (
            <EmptyState message="Este cuadre no tiene transacciones." />
          ) : (
            <>
              {(() => {
                const rows = transactions.data ?? [];
                const sum = (
                  key:
                    | "total_usd"
                    | "paid_usd"
                    | "balance_usd"
                    | "cash_usd"
                    | "card_usd"
                    | "biopago_usd"
                    | "credit_usd",
                ) => rows.reduce((acc, tx) => acc + Number(tx[key] ?? 0), 0);
                return (
                  <div className="grid grid-cols-2 gap-3 px-5 py-4 sm:grid-cols-4">
                    <SummaryItem
                      label="Efectivo"
                      value={formatMoney(String(sum("cash_usd")), "USD")}
                    />
                    <SummaryItem
                      label="Tarjeta"
                      value={formatMoney(String(sum("card_usd")), "USD")}
                    />
                    <SummaryItem
                      label="BioPago"
                      value={formatMoney(String(sum("biopago_usd")), "USD")}
                    />
                    <SummaryItem
                      label="Fiado (crédito)"
                      value={formatMoney(String(sum("credit_usd")), "USD")}
                    />
                  </div>
                );
              })()}
              <Table
                headers={[
                  "Documento",
                  "Tipo",
                  "Cliente",
                  "Total",
                  "Efectivo",
                  "Tarjeta",
                  "BioPago",
                  "Fiado",
                ]}
              >
                {transactions.data?.map((tx) => (
                  <tr key={tx.id}>
                    <td className="px-5 py-3 font-medium text-primary">
                      {tx.number}
                    </td>
                    <td className="px-5 py-3">
                      {tx.source === "invoice" ? "Factura" : "Pedido"}
                    </td>
                    <td className="px-5 py-3">{tx.party_name ?? "—"}</td>
                    <td className="px-5 py-3 font-semibold">
                      {formatMoney(tx.total_usd, "USD")}
                    </td>
                    <td className="px-5 py-3">
                      {formatMoney(tx.cash_usd, "USD")}
                    </td>
                    <td className="px-5 py-3">
                      {formatMoney(tx.card_usd, "USD")}
                    </td>
                    <td className="px-5 py-3">
                      {formatMoney(tx.biopago_usd, "USD")}
                    </td>
                    <td className="px-5 py-3 text-amber-700">
                      {formatMoney(tx.credit_usd, "USD")}
                    </td>
                  </tr>
                ))}
              </Table>
            </>
          )}
        </Card>
      )}
    </div>
  );
}

function SummaryItem({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-slate-50 p-3 dark:bg-slate-800">
      <div className="text-xs text-slate-500 dark:text-slate-400">{label}</div>
      <div className="text-base font-semibold text-slate-900 dark:text-slate-100">
        {value}
      </div>
    </div>
  );
}
