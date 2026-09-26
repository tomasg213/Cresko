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
  Input,
  LoadingState,
  Select,
  Table,
} from "@/components/ui";
import { useFeedback } from "@/components/feedback";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type { AdminOrg } from "@/lib/types";
import { cn } from "@/lib/utils";

type Section = "customers" | "demos";

const PAYMENT_LABEL: Record<AdminOrg["payment_status"], string> = {
  paid: "Pagado",
  free: "Acceso libre",
  pending: "Pendiente",
};

const PAYMENT_BADGE: Record<AdminOrg["payment_status"], string> = {
  paid: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300",
  free: "bg-sky-100 text-sky-700 dark:bg-sky-900/40 dark:text-sky-300",
  pending:
    "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300",
};

function formatTimeLeft(adminOrg: AdminOrg): string {
  if (!adminOrg.demo_expires_at) return "—";
  const remaining = Date.parse(adminOrg.demo_expires_at) - Date.now();
  if (remaining <= 0) return "Expirada";
  const totalSeconds = Math.floor(remaining / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

export default function AdminPage() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const { notify } = useFeedback();
  const [section, setSection] = useState<Section>("customers");
  const [query, setQuery] = useState("");

  const orgs = useQuery({
    queryKey: ["admin-orgs", orgId],
    queryFn: () => api<AdminOrg[]>(`/v1/admin/orgs`, { orgId }),
    enabled: !!orgId,
    retry: false,
  });

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const rows = (orgs.data ?? []).filter((o) =>
      section === "demos" ? o.is_demo : !o.is_demo,
    );
    if (!q) return rows;
    return rows.filter(
      (o) =>
        o.org_name.toLowerCase().includes(q) ||
        o.owner_email.toLowerCase().includes(q),
    );
  }, [orgs.data, query, section]);

  const counts = useMemo(() => {
    const data = orgs.data ?? [];
    return {
      customers: data.filter((o) => !o.is_demo).length,
      demos: data.filter((o) => o.is_demo).length,
    };
  }, [orgs.data]);

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

      <div className="flex items-center gap-2 border-b border-slate-200 dark:border-slate-700">
        <TabButton
          active={section === "customers"}
          onClick={() => setSection("customers")}
        >
          Clientes
          <CountBadge>{counts.customers}</CountBadge>
        </TabButton>
        <TabButton
          active={section === "demos"}
          onClick={() => setSection("demos")}
        >
          Demos
          <CountBadge>{counts.demos}</CountBadge>
        </TabButton>
      </div>

      <Card>
        <CardHeader title={section === "demos" ? "Cuentas demo" : "Clientes"} />
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
            <EmptyState
              message={
                section === "demos" ? "Sin cuentas demo." : "Sin clientes."
              }
            />
          ) : (
            <Table
              headers={
                section === "demos"
                  ? [
                      "Comercio",
                      "Correo",
                      "Creado",
                      "Expira",
                      "Acceso",
                      "Pago",
                      "Acciones",
                    ]
                  : [
                      "Comercio",
                      "Correo",
                      "Miembros",
                      "Creado",
                      "Pago",
                      "Acceso",
                      "Acciones",
                    ]
              }
            >
              {filtered.map((adminOrg) => (
                <AdminRow
                  key={adminOrg.org_id}
                  adminOrg={adminOrg}
                  isDemo={section === "demos"}
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

function TabButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "-mb-px flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-medium transition-colors",
        active
          ? "border-primary text-primary"
          : "border-transparent text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200",
      )}
    >
      {children}
    </button>
  );
}

function CountBadge({ children }: { children: React.ReactNode }) {
  return (
    <span className="rounded-full bg-slate-200 px-2 py-0.5 text-xs font-semibold text-slate-600 dark:bg-slate-700 dark:text-slate-300">
      {children}
    </span>
  );
}

function AdminRow({
  adminOrg,
  isDemo,
  onUpdate,
}: {
  adminOrg: AdminOrg;
  isDemo: boolean;
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
      {!isDemo && <td className="px-5 py-3">{adminOrg.member_count}</td>}
      <td className="px-5 py-3 text-slate-600 dark:text-slate-400">
        {new Date(adminOrg.created_at).toLocaleDateString("es-VE")}
      </td>
      {isDemo && (
        <td className="px-5 py-3">
          <span
            className={cn(
              "inline-flex rounded-full px-2 py-0.5 text-xs font-medium",
              adminOrg.access_status === "suspended" ||
                adminOrg.time_left === null
                ? "bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300"
                : "bg-indigo-100 text-indigo-700 dark:bg-indigo-900/40 dark:text-indigo-300",
            )}
          >
            {adminOrg.access_status === "suspended"
              ? "Expirada"
              : formatTimeLeft(adminOrg)}
          </span>
        </td>
      )}
      {!isDemo && (
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
      )}
      <td className="px-5 py-3">
        <Select
          value={accessStatus}
          onChange={(event) =>
            setAccessStatus(event.target.value as AdminOrg["access_status"])
          }
          className={cn(isDemo ? "w-36" : "w-32")}
        >
          <option value="active">Activo</option>
          <option value="suspended">Suspendido</option>
        </Select>
      </td>
      {isDemo && (
        <td className="px-5 py-3">
          <span
            className={cn(
              "inline-flex rounded-full px-2 py-0.5 text-xs font-medium",
              PAYMENT_BADGE[paymentStatus],
            )}
          >
            {PAYMENT_LABEL[paymentStatus]}
          </span>
        </td>
      )}
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
