"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Search } from "lucide-react";
import { useMemo, useState } from "react";

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
import type { AdminOrg } from "@/lib/types";

const PAYMENT_LABEL: Record<string, string> = {
  paid: "Pagado",
  free: "Acceso libre",
  pending: "Pendiente",
};

const ACCESS_LABEL: Record<string, string> = {
  active: "Activo",
  suspended: "Suspendido",
};

export default function AdminPage() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const { notify } = useFeedback();
  const [query, setQuery] = useState("");

  const orgs = useQuery({
    queryKey: ["admin-orgs", orgId],
    queryFn: () => api<AdminOrg[]>(`/v1/admin/orgs`, { orgId }),
    enabled: !!orgId,
    retry: false,
  });

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return orgs.data ?? [];
    return (orgs.data ?? []).filter(
      (o) =>
        o.org_name.toLowerCase().includes(q) ||
        o.owner_email.toLowerCase().includes(q),
    );
  }, [orgs.data, query]);

  async function updateStatus(
    adminOrg: AdminOrg,
    patch: Partial<
      Pick<AdminOrg, "access_status" | "payment_status" | "notes">
    >,
  ) {
    try {
      await api(`/v1/admin/orgs/${adminOrg.org_id}/status`, {
        method: "POST",
        orgId,
        body: patch,
      });
      await queryClient.invalidateQueries({ queryKey: ["admin-orgs", orgId] });
      notify("Estado actualizado.", "success");
    } catch (err) {
      notify(err instanceof Error ? err.message : "No se pudo actualizar");
    }
  }

  if (orgs.isError) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
          Administración
        </h1>
        <ErrorState
          message={
            (orgs.error as Error).message.includes("access denied")
              ? "No tienes permisos de administración del portal."
              : (orgs.error as Error).message
          }
          onRetry={() => orgs.refetch()}
        />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
        Administración de cuentas
      </h1>

      <Card>
        <CardHeader title="Clientes" />
        <div className="px-5 py-4">
          <div className="relative mb-4 max-w-sm">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
            <Input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Buscar por comercio o correo..."
              className="pl-9"
            />
          </div>
          {orgs.isLoading ? (
            <LoadingState />
          ) : filtered.length === 0 ? (
            <EmptyState message="Sin clientes." />
          ) : (
            <Table
              headers={[
                "Comercio",
                "Correo",
                "Miembros",
                "Creado",
                "Pago",
                "Acceso",
                "Acciones",
              ]}
            >
              {filtered.map((adminOrg) => (
                <AdminRow
                  key={adminOrg.org_id}
                  adminOrg={adminOrg}
                  onUpdate={(patch) => updateStatus(adminOrg, patch)}
                />
              ))}
            </Table>
          )}
        </div>
      </Card>
    </div>
  );
}

function AdminRow({
  adminOrg,
  onUpdate,
}: {
  adminOrg: AdminOrg;
  onUpdate: (
    patch: Partial<
      Pick<AdminOrg, "access_status" | "payment_status" | "notes">
    >,
  ) => void;
}) {
  const [paymentStatus, setPaymentStatus] = useState<
    AdminOrg["payment_status"]
  >(adminOrg.payment_status);
  const [accessStatus, setAccessStatus] = useState<AdminOrg["access_status"]>(
    adminOrg.access_status,
  );
  const [notes, setNotes] = useState(adminOrg.notes ?? "");

  const dirty =
    paymentStatus !== adminOrg.payment_status ||
    accessStatus !== adminOrg.access_status ||
    notes !== (adminOrg.notes ?? "");

  return (
    <tr>
      <td className="px-5 py-3">
        <div className="font-medium text-slate-900 dark:text-slate-100">
          {adminOrg.org_name}
        </div>
        <div className="text-xs text-slate-500 dark:text-slate-400">
          {adminOrg.owner_name || "—"}
        </div>
      </td>
      <td className="px-5 py-3">{adminOrg.owner_email}</td>
      <td className="px-5 py-3">{adminOrg.member_count}</td>
      <td className="px-5 py-3 text-slate-600 dark:text-slate-400">
        {new Date(adminOrg.created_at).toLocaleDateString("es-VE")}
      </td>
      <td className="px-5 py-3">
        <Select
          value={paymentStatus}
          onChange={(event) =>
            setPaymentStatus(event.target.value as AdminOrg["payment_status"])
          }
          className="w-36"
        >
          <option value="paid">Pagado</option>
          <option value="free">Acceso libre</option>
          <option value="pending">Pendiente</option>
        </Select>
      </td>
      <td className="px-5 py-3">
        <Select
          value={accessStatus}
          onChange={(event) =>
            setAccessStatus(event.target.value as AdminOrg["access_status"])
          }
          className="w-32"
        >
          <option value="active">Activo</option>
          <option value="suspended">Suspendido</option>
        </Select>
      </td>
      <td className="px-5 py-3">
        <div className="flex items-center gap-2">
          <Input
            value={notes}
            onChange={(event) => setNotes(event.target.value)}
            placeholder="Nota..."
            className="w-40"
          />
          <Button
            variant="secondary"
            className="px-3 py-1 text-xs"
            disabled={!dirty}
            onClick={() =>
              onUpdate({
                payment_status: paymentStatus,
                access_status: accessStatus,
                notes,
              })
            }
          >
            Guardar
          </Button>
        </div>
      </td>
    </tr>
  );
}
