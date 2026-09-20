"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus } from "lucide-react";
import { useState } from "react";

import { Button, Card, CardHeader, EmptyState, ErrorState, Field, Input, LoadingState, Select, Table } from "@/components/ui";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import type { Party } from "@/lib/types";

export default function PartiesPage() {
  const { orgId } = useOrg();
  const [kind, setKind] = useState<"customer" | "supplier">("customer");
  const [open, setOpen] = useState(false);

  const parties = useQuery({
    queryKey: ["parties", orgId, kind],
    queryFn: () => api<Party[]>(`/v1/parties?kind=${kind}`, { orgId }),
    enabled: !!orgId,
  });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">Clientes y proveedores</h1>
        <Button onClick={() => setOpen(true)}>
          <Plus className="h-4 w-4" />
          Nuevo
        </Button>
      </div>

      <div className="flex gap-2">
        {(["customer", "supplier"] as const).map((option) => (
          <button
            key={option}
            onClick={() => setKind(option)}
            className={`rounded-lg px-4 py-2 text-sm font-medium ${
              kind === option ? "bg-primary text-white" : "bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 border border-slate-300 dark:border-slate-600"
            }`}
          >
            {option === "customer" ? "Clientes" : "Proveedores"}
          </button>
        ))}
      </div>

      <Card>
        <CardHeader title={kind === "customer" ? "Clientes" : "Proveedores"} />
        {parties.isLoading ? (
          <LoadingState />
        ) : parties.isError ? (
          <ErrorState message={parties.error.message} onRetry={() => parties.refetch()} />
        ) : parties.data?.length === 0 ? (
          <EmptyState message="Sin registros." />
        ) : (
          <Table headers={["Nombre", "Documento", "Teléfono", "Correo"]}>
            {parties.data?.map((party) => (
              <tr key={party.id}>
                <td className="px-5 py-3 font-medium">{party.name}</td>
                <td className="px-5 py-3 text-slate-600 dark:text-slate-400">
                  {party.document_type.toUpperCase()} {party.document_id ?? ""}
                </td>
                <td className="px-5 py-3">{party.phone}</td>
                <td className="px-5 py-3">{party.email}</td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      {open && (
        <PartyModal
          kind={kind}
          onClose={() => setOpen(false)}
          onCreated={() => {
            setOpen(false);
            parties.refetch();
          }}
        />
      )}
    </div>
  );
}

function PartyModal({
  kind,
  onClose,
  onCreated,
}: {
  kind: "customer" | "supplier";
  onClose: () => void;
  onCreated: () => void;
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
      await api("/v1/parties", {
        method: "POST",
        orgId,
        body: {
          name,
          document_type: documentType,
          document_id: documentId || null,
          phone: phone || null,
          email: email || null,
          is_customer: kind === "customer",
          is_supplier: kind === "supplier",
        },
      });
      onCreated();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo guardar");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <form onSubmit={handleSubmit} className="mt-16 w-full max-w-md rounded-xl bg-white dark:bg-slate-800 shadow-lg">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
            Nuevo {kind === "customer" ? "cliente" : "proveedor"}
          </h2>
        </div>
        <div className="space-y-4 px-6 py-5">
          <Field label="Nombre">
            <Input required value={name} onChange={(event) => setName(event.target.value)} />
          </Field>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label="Tipo de documento">
              <Select value={documentType} onChange={(event) => setDocumentType(event.target.value)}>
                <option value="rif">RIF</option>
                <option value="ci">Cédula</option>
                <option value="passport">Pasaporte</option>
                <option value="other">Otro</option>
              </Select>
            </Field>
            <Field label="Número">
              <Input value={documentId} onChange={(event) => setDocumentId(event.target.value)} />
            </Field>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label="Teléfono">
              <Input value={phone} onChange={(event) => setPhone(event.target.value)} />
            </Field>
            <Field label="Correo">
              <Input type="email" value={email} onChange={(event) => setEmail(event.target.value)} />
            </Field>
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