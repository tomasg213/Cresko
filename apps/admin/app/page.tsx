"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { api, type AdminOrg } from "@/lib/api";

export default function AdminDashboard() {
  const router = useRouter();
  const [orgs, setOrgs] = useState<AdminOrg[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [editing, setEditing] = useState<Record<string, AdminOrg>>({});

  useEffect(() => {
    let active = true;
    api<AdminOrg[]>("/v1/admin/orgs")
      .then((rows) => {
        if (active) {
          setOrgs(rows);
          const map: Record<string, AdminOrg> = {};
          for (const row of rows) map[row.org_id] = row;
          setEditing(map);
        }
      })
      .catch((err) => {
        if (active) {
          setError(
            err instanceof Error ? err.message : "No se pudo cargar",
          );
        }
      });
    return () => {
      active = false;
    };
  }, []);

  const filtered = orgs?.filter((o) => {
    const q = query.trim().toLowerCase();
    if (!q) return true;
    return (
      o.org_name.toLowerCase().includes(q) ||
      o.owner_email.toLowerCase().includes(q)
    );
  });

  async function save(id: string) {
    const row = editing[id];
    if (!row) return;
    setError(null);
    try {
      await api(`/v1/admin/orgs/${id}/status`, {
        method: "POST",
        body: {
          access_status: row.access_status,
          payment_status: row.payment_status,
          notes: row.notes,
        },
      });
      const refreshed = await api<AdminOrg[]>("/v1/admin/orgs");
      const map: Record<string, AdminOrg> = {};
      for (const r of refreshed) map[r.org_id] = r;
      setOrgs(refreshed);
      setEditing(map);
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo guardar");
    }
  }

  function patch(id: string, patch: Partial<AdminOrg>) {
    setEditing((current) => ({
      ...current,
      [id]: { ...current[id], ...patch },
    }));
  }

  return (
    <main className="min-h-screen p-6">
      <div className="mx-auto max-w-5xl">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-semibold text-slate-900">
              Cuentas de clientes
            </h1>
            <p className="text-sm text-slate-500">
              Administra pago y acceso de cada comercio.
            </p>
          </div>
          <button
            onClick={async () => {
              const { createClient } = await import("@/lib/supabase");
              const supabase = createClient();
              await supabase.auth.signOut();
              router.push("/login");
            }}
            className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm text-slate-600 hover:bg-slate-100"
          >
            Cerrar sesión
          </button>
        </div>

        {error && (
          <p className="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-700">
            {error}
          </p>
        )}

        {orgs === null ? (
          <p className="mt-8 text-sm text-slate-500">Cargando...</p>
        ) : (
          <>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Buscar por comercio o correo..."
              className="mt-6 w-full max-w-sm rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-teal-600"
            />
            <div className="mt-4 overflow-x-auto rounded-xl border border-slate-200 bg-white">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-200 text-left text-xs uppercase text-slate-500">
                    <th className="px-4 py-3">Comercio</th>
                    <th className="px-4 py-3">Correo</th>
                    <th className="px-4 py-3">Miembros</th>
                    <th className="px-4 py-3">Creado</th>
                    <th className="px-4 py-3">Pago</th>
                    <th className="px-4 py-3">Acceso</th>
                    <th className="px-4 py-3">Nota</th>
                    <th className="px-4 py-3"></th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {filtered?.map((row) => {
                    const edit = editing[row.org_id] ?? row;
                    return (
                      <tr key={row.org_id}>
                        <td className="px-4 py-3 font-medium">
                          {edit.org_name}
                          {edit.owner_name && (
                            <div className="text-xs text-slate-400">
                              {edit.owner_name}
                            </div>
                          )}
                        </td>
                        <td className="px-4 py-3">{edit.owner_email}</td>
                        <td className="px-4 py-3">{edit.member_count}</td>
                        <td className="px-4 py-3 text-slate-500">
                          {new Date(edit.created_at).toLocaleDateString("es-VE")}
                        </td>
                        <td className="px-4 py-3">
                          <select
                            value={edit.payment_status}
                            onChange={(e) =>
                              patch(row.org_id, {
                                payment_status: e.target.value as AdminOrg["payment_status"],
                              })
                            }
                            className="rounded-lg border border-slate-300 px-2 py-1 text-xs"
                          >
                            <option value="paid">Pagado</option>
                            <option value="free">Acceso libre</option>
                            <option value="pending">Pendiente</option>
                          </select>
                        </td>
                        <td className="px-4 py-3">
                          <select
                            value={edit.access_status}
                            onChange={(e) =>
                              patch(row.org_id, {
                                access_status: e.target.value as AdminOrg["access_status"],
                              })
                            }
                            className="rounded-lg border border-slate-300 px-2 py-1 text-xs"
                          >
                            <option value="active">Activo</option>
                            <option value="suspended">Suspendido</option>
                          </select>
                        </td>
                        <td className="px-4 py-3">
                          <input
                            value={edit.notes ?? ""}
                            onChange={(e) =>
                              patch(row.org_id, { notes: e.target.value })
                            }
                            placeholder="Nota..."
                            className="rounded-lg border border-slate-300 px-2 py-1 text-xs"
                          />
                        </td>
                        <td className="px-4 py-3">
                          <button
                            onClick={() => save(row.org_id)}
                            className="rounded-lg bg-teal-700 px-3 py-1 text-xs font-medium text-white hover:bg-teal-800"
                          >
                            Guardar
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </main>
  );
}