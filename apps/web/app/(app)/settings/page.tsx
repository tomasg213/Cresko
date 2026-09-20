"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Trash2 } from "lucide-react";
import { useRef, useState } from "react";

import { Button, Card, CardHeader, EmptyState, ErrorState, Field, Input, LoadingState, Select, Table } from "@/components/ui";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type { FxRate, Invitation, Member, Organization, Permission, PermissionInfo, Role } from "@/lib/types";
import { formatMoney } from "@/lib/utils";

const PERMISSION_GROUPS: { label: string; keys: Permission[] }[] = [
  { label: "Catálogo", keys: ["catalog.read", "catalog.write"] },
  { label: "Inventario", keys: ["inventory.read", "inventory.write"] },
  { label: "Ventas (POS)", keys: ["sales.read", "sales.checkout", "sales.credit"] },
  { label: "Compras", keys: ["purchasing.read", "purchasing.write", "purchasing.receive"] },
  { label: "Finanzas", keys: ["finance.read", "finance.receive", "finance.pay"] },
  { label: "Reposición", keys: ["replenishment.read", "replenishment.write"] },
  { label: "Administración", keys: ["members.manage", "roles.manage", "org.manage"] },
];

type RoleModalState = { mode: "create" } | { mode: "edit"; role: Role } | null;

export default function SettingsPage() {
  const { orgId, can } = useOrg();
  const queryClient = useQueryClient();
  const [tab, setTab] = useState<"org" | "roles" | "members">("org");
  const [roleOpen, setRoleOpen] = useState<RoleModalState>(null);
  const [inviteOpen, setInviteOpen] = useState(false);

  const roles = useQuery({
    queryKey: ["roles", orgId],
    queryFn: () => api<Role[]>(`/v1/roles`, { orgId }),
    enabled: !!orgId && can("roles.manage"),
  });
  const members = useQuery({
    queryKey: ["members", orgId],
    queryFn: () => api<Member[]>(`/v1/members`, { orgId }),
    enabled: !!orgId && can("members.manage"),
  });

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">Configuración</h1>

      <div className="flex gap-2">
        <button
          onClick={() => setTab("org")}
          className={`rounded-lg px-4 py-2 text-sm font-medium ${
            tab === "org" ? "bg-primary text-white" : "bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-200"
          }`}
        >
          Comercio
        </button>
        <button
          onClick={() => setTab("roles")}
          className={`rounded-lg px-4 py-2 text-sm font-medium ${
            tab === "roles" ? "bg-primary text-white" : "bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-200"
          }`}
        >
          Roles
        </button>
        <button
          onClick={() => setTab("members")}
          className={`rounded-lg px-4 py-2 text-sm font-medium ${
            tab === "members" ? "bg-primary text-white" : "bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-200"
          }`}
        >
          Miembros
        </button>
      </div>

      {tab === "org" ? (
        <CommerceSettings />
      ) : tab === "roles" && can("roles.manage") ? (
        <Card>
          <CardHeader
            title="Roles personalizados"
            action={
              <Button onClick={() => setRoleOpen({ mode: "create" })}>
                <Plus className="h-4 w-4" />
                Nuevo rol
              </Button>
            }
          />
          {roles.isLoading ? (
            <LoadingState />
          ) : roles.isError ? (
            <ErrorState message={roles.error.message} onRetry={() => roles.refetch()} />
          ) : roles.data?.length === 0 ? (
            <EmptyState message="Sin roles creados." />
          ) : (
            <div className="divide-y divide-slate-100 dark:divide-slate-800">
              {roles.data?.map((role) => (
                <div key={role.id} className="flex items-start justify-between px-5 py-4">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-slate-900 dark:text-slate-100">{role.name}</span>
                      {role.is_system && (
                        <span className="rounded-full bg-slate-100 dark:bg-slate-800 px-2 py-0.5 text-xs text-slate-500 dark:text-slate-400">Sistema</span>
                      )}
                    </div>
                    <div className="mt-1 text-xs text-slate-500 dark:text-slate-400">
                      {role.permissions.length} permisos ·{" "}
                      {role.permissions.slice(0, 4).join(", ")}
                      {role.permissions.length > 4 ? ", ..." : ""}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <Button variant="secondary" onClick={() => setRoleOpen({ mode: "edit", role })}>
                      Editar
                    </Button>
                    {!role.is_system && (
                      <Button
                        variant="danger"
                        onClick={async () => {
                          await api(`/v1/roles/${role.id}`, { method: "DELETE", orgId });
                          queryClient.invalidateQueries({ queryKey: ["roles", orgId] });
                        }}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      ) : tab === "members" && can("members.manage") ? (
        <Card>
          <CardHeader
            title="Miembros del comercio"
            action={
              <Button onClick={() => setInviteOpen(true)}>
                <Plus className="h-4 w-4" />
                Invitar
              </Button>
            }
          />
          {members.isLoading ? (
            <LoadingState />
          ) : members.isError ? (
            <ErrorState message={members.error.message} onRetry={() => members.refetch()} />
          ) : members.data?.length === 0 ? (
            <EmptyState message="Sin miembros." />
          ) : (
            <Table headers={["Correo", "Rol"]}>
              {members.data?.map((member) => (
                <tr key={member.id}>
                  <td className="px-5 py-3 font-medium">{member.email}</td>
                  <td className="px-5 py-3">{member.role_name}</td>
                </tr>
              ))}
            </Table>
          )}
          <PendingInvitations />
        </Card>
      ) : (
        <Card>
          <EmptyState message="No tienes permisos para administrar roles y miembros." />
        </Card>
      )}

      {roleOpen && (
        <RoleModal
          initial={roleOpen.mode === "edit" ? roleOpen.role : null}
          onClose={() => setRoleOpen(null)}
          onSaved={() => {
            setRoleOpen(null);
            queryClient.invalidateQueries({ queryKey: ["roles", orgId] });
          }}
        />
      )}
      {inviteOpen && (
        <InviteModal
          onClose={() => setInviteOpen(false)}
          onInvited={() => {
            setInviteOpen(false);
            queryClient.invalidateQueries({ queryKey: ["members", orgId] });
          }}
        />
      )}
    </div>
  );
}

function PendingInvitations() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const pending = useQuery({
    queryKey: ["my-invitations"],
    queryFn: () => api<Invitation[]>(`/v1/invitations`, { orgId: null }),
  });

  if (pending.isLoading || pending.data?.length === 0) return null;

  return (
    <div className="border-t border-slate-200 dark:border-slate-700 px-5 py-4">
      <h3 className="mb-2 text-sm font-semibold text-slate-700 dark:text-slate-200">Invitaciones pendientes</h3>
      {pending.data?.map((invitation) => (
        <div key={invitation.id} className="flex items-center justify-between py-2">
          <span className="text-sm text-slate-600 dark:text-slate-400">
            {invitation.email} · {invitation.org_id.slice(0, 8)}
          </span>
          <Button
            onClick={async () => {
              await api(`/v1/members/invitations/accept`, {
                method: "POST",
                orgId: null,
                body: { token: invitation.token },
              });
              queryClient.invalidateQueries({ queryKey: ["my-invitations"] });
            }}
          >
            Aceptar
          </Button>
        </div>
      ))}
    </div>
  );
}

function RoleModal({
  initial,
  onClose,
  onSaved,
}: {
  initial: Role | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { orgId } = useOrg();
  const [name, setName] = useState(initial?.name ?? "");
  const [selected, setSelected] = useState<Permission[]>(initial?.permissions ?? []);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const permissions = useQuery({
    queryKey: ["permissions"],
    queryFn: () => api<PermissionInfo[]>(`/v1/roles/permissions`, { orgId }),
    enabled: !!orgId,
  });

  function toggle(permission: Permission) {
    setSelected((current) =>
      current.includes(permission) ? current.filter((p) => p !== permission) : [...current, permission],
    );
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const body = { name, permissions: selected };
      if (initial) {
        await api(`/v1/roles/${initial.id}`, { method: "PUT", orgId, body });
      } else {
        await api(`/v1/roles`, { method: "POST", orgId, body });
      }
      onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo guardar el rol");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <form onSubmit={handleSubmit} className="mt-8 w-full max-w-lg rounded-xl bg-white dark:bg-slate-800 shadow-lg">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">{initial ? "Editar rol" : "Nuevo rol"}</h2>
        </div>
        <div className="space-y-4 px-6 py-5">
          <Field label="Nombre del rol">
            <Input required value={name} onChange={(event) => setName(event.target.value)} placeholder="Ej: Cajero, Bodeguero, Pedidos" />
          </Field>
          <div className="space-y-4">
            {PERMISSION_GROUPS.map((group) => (
              <div key={group.label}>
                <h3 className="mb-1 text-sm font-semibold text-slate-700 dark:text-slate-200">{group.label}</h3>
                <div className="space-y-1">
                  {group.keys.map((key) => {
                    const info = permissions.data?.find((p) => p.code === key);
                    return (
                      <label key={key} className="flex items-start gap-2 text-sm">
                        <input
                          type="checkbox"
                          className="mt-0.5"
                          checked={selected.includes(key)}
                          onChange={() => toggle(key)}
                        />
                        <span>
                          <span className="font-medium text-slate-800 dark:text-slate-100">{key}</span>
                          {info && <span className="block text-xs text-slate-500 dark:text-slate-400">{info.description}</span>}
                        </span>
                      </label>
                    );
                  })}
                </div>
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

function InviteModal({ onClose, onInvited }: { onClose: () => void; onInvited: () => void }) {
  const { orgId } = useOrg();
  const [email, setEmail] = useState("");
  const [roleId, setRoleId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const roles = useQuery({
    queryKey: ["roles", orgId],
    queryFn: () => api<Role[]>(`/v1/roles`, { orgId }),
    enabled: !!orgId,
  });

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await api(`/v1/members/invitations`, {
        method: "POST",
        orgId,
        body: { email, role_id: roleId },
      });
      onInvited();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo enviar la invitación");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <form onSubmit={handleSubmit} className="mt-16 w-full max-w-md rounded-xl bg-white dark:bg-slate-800 shadow-lg">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">Invitar miembro</h2>
        </div>
        <div className="space-y-4 px-6 py-5">
          <Field label="Correo electrónico del empleado">
            <Input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} />
          </Field>
          <Field label="Rol">
            <Select required value={roleId} onChange={(event) => setRoleId(event.target.value)}>
              <option value="">Seleccionar...</option>
              {roles.data?.map((role) => (
                <option key={role.id} value={role.id}>
                  {role.name}
                </option>
              ))}
            </Select>
          </Field>
          <p className="text-xs text-slate-500 dark:text-slate-400">
            El empleado debe crear una cuenta con ese correo y aceptará la invitación al entrar.
          </p>
          {error && <p className="text-sm text-red-600">{error}</p>}
        </div>
        <div className="flex justify-end gap-3 border-t border-slate-200 dark:border-slate-700 px-6 py-4">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancelar
          </Button>
          <Button type="submit" disabled={submitting}>
            {submitting ? "Enviando..." : "Enviar invitación"}
          </Button>
        </div>
      </form>
    </div>
  );
}

function CommerceSettings() {
  const { orgId, can, refreshOrg } = useOrg();
  const [name, setName] = useState("");
  const [legalName, setLegalName] = useState("");
  const [taxId, setTaxId] = useState("");
  const [currency, setCurrency] = useState<"VES" | "USD">("VES");
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [loaded, setLoaded] = useState(false);

  const org = useQuery({
    queryKey: ["org", orgId],
    queryFn: () => api<Organization>(`/v1/orgs`, { orgId }),
    enabled: !!orgId,
  });

  if (org.data && !loaded) {
    setName(org.data.name);
    setLegalName(org.data.legal_name ?? "");
    setTaxId(org.data.tax_id ?? "");
    setCurrency(org.data.default_currency);
    setLoaded(true);
  }

  if (!can("org.manage")) {
    return (
      <Card>
        <EmptyState message="No tienes permisos para modificar la configuración del comercio." />
      </Card>
    );
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    setMessage(null);
    try {
      await api("/v1/orgs", {
        method: "PATCH",
        orgId,
        body: {
          name,
          legal_name: legalName || null,
          tax_id: taxId || null,
          default_currency: currency,
        },
      });
      setMessage("Datos del comercio guardados.");
      refreshOrg();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo guardar");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <Card>
        <CardHeader title="Datos del comercio" />
      <form onSubmit={handleSubmit} className="space-y-4 px-5 py-5 max-w-xl">
        <Field label="Nombre de la empresa o comercio">
          <Input required value={name} onChange={(event) => setName(event.target.value)} />
        </Field>
        <Field label="Razón social">
          <Input value={legalName} onChange={(event) => setLegalName(event.target.value)} />
        </Field>
        <Field label="RIF">
          <Input value={taxId} onChange={(event) => setTaxId(event.target.value)} />
        </Field>
        <Field label="Moneda por defecto">
          <Select value={currency} onChange={(event) => setCurrency(event.target.value as "VES" | "USD")}>
            <option value="VES">Bolívares (VES)</option>
            <option value="USD">Dólares (USD)</option>
          </Select>
        </Field>
        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}
        <Button type="submit" disabled={submitting}>
          {submitting ? "Guardando..." : "Guardar cambios"}
        </Button>
      </form>
      </Card>
      <FxRateCard />
      <BackupCard />
    </>
  );
}

function FxRateCard() {
  const { orgId } = useOrg();
  const queryClient = useQueryClient();
  const [rate, setRate] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const current = useQuery({
    queryKey: ["fx-rate", orgId],
    queryFn: () => api<FxRate>(`/v1/fx/rate`, { orgId }),
    enabled: !!orgId,
    retry: false,
  });

  async function saveManual(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    setMessage(null);
    try {
      await api(`/v1/fx/rate`, { method: "POST", orgId, body: { rate: Number(rate) } });
      setMessage("Tasa guardada.");
      setRate("");
      queryClient.invalidateQueries({ queryKey: ["fx-rate", orgId] });
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo guardar la tasa");
    } finally {
      setSubmitting(false);
    }
  }

  async function fetchFromBcv() {
    setSubmitting(true);
    setError(null);
    setMessage(null);
    try {
      await api(`/v1/fx/fetch`, { method: "POST", orgId });
      setMessage("Tasa obtenida del BCV.");
      queryClient.invalidateQueries({ queryKey: ["fx-rate", orgId] });
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo obtener la tasa del BCV");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Card>
      <CardHeader title="Tasa de cambio (BCV)" />
      <div className="space-y-4 px-5 py-5 max-w-xl">
        <div className="text-sm">
          {current.data ? (
            <>
              <span className="font-semibold text-slate-900 dark:text-slate-100">
                {formatMoney(current.data.rate, "VES")} Bs. por USD
              </span>
              <span className="ml-2 text-xs text-slate-500 dark:text-slate-400">
                ({current.data.rate_date} · {current.data.source === "bcv" ? "BCV" : "manual"})
              </span>
            </>
          ) : (
            <span className="text-amber-600">
              {current.isLoading ? "Consultando..." : "Sin tasa registrada"}
            </span>
          )}
        </div>

        <form onSubmit={saveManual} className="flex items-end gap-3">
          <Field label="Nueva tasa (Bs. por USD)">
            <Input
              type="number"
              step="0.01"
              min="0"
              required
              value={rate}
              onChange={(event) => setRate(event.target.value)}
            />
          </Field>
          <Button type="submit" disabled={submitting}>
            {submitting ? "Guardando..." : "Guardar tasa"}
          </Button>
        </form>

        <Button variant="secondary" onClick={fetchFromBcv} disabled={submitting}>
          Obtener tasa oficial del día (dolarapi.com)
        </Button>

        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}
      </div>
    </Card>
  );
}

function BackupCard() {
  const { orgId } = useOrg();
  const fileRef = useRef<HTMLInputElement>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [working, setWorking] = useState(false);

  async function exportBackup() {
    setWorking(true);
    setError(null);
    setMessage(null);
    try {
      const data = await api<Record<string, unknown>>(`/v1/backup/export`, { orgId });
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `cresko-backup-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);
      setMessage("Respaldo descargado. Guárdalo en un lugar seguro.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo exportar el respaldo");
    } finally {
      setWorking(false);
    }
  }

  async function handleImportFile(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    if (!window.confirm("Importar reemplazará TODOS los datos actuales del comercio. ¿Continuar?")) {
      if (fileRef.current) fileRef.current.value = "";
      return;
    }
    setWorking(true);
    setError(null);
    setMessage(null);
    try {
      const text = await file.text();
      const data = JSON.parse(text);
      const result = await api<{ message: string }>(`/v1/backup/import`, {
        method: "POST",
        orgId,
        body: { data },
      });
      setMessage(result.message);
      window.location.reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo importar el respaldo");
    } finally {
      setWorking(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  return (
    <Card>
      <CardHeader title="Respaldo de datos" />
      <div className="space-y-4 px-5 py-5 max-w-xl">
        <p className="text-sm text-slate-600 dark:text-slate-400">
          Exporta toda la información del comercio (catálogo, inventario, facturas, cuentas, roles) a
          un archivo para resguardarla. Sirve como medida de seguridad ante un formateo, cambio de
          servidor, base de datos o si cambias de servicio.
        </p>
        <div className="flex flex-wrap items-center gap-3">
          <Button onClick={exportBackup} disabled={working}>
            {working ? "Procesando..." : "Exportar respaldo"}
          </Button>
          <Button variant="secondary" onClick={() => fileRef.current?.click()} disabled={working}>
            Importar respaldo
          </Button>
          <input
            ref={fileRef}
            type="file"
            accept="application/json,.json"
            className="hidden"
            onChange={handleImportFile}
          />
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}
      </div>
    </Card>
  );
}