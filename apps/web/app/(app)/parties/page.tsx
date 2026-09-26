"use client";

import { useQuery } from "@tanstack/react-query";
import { Pencil, Plus, Trash2 } from "lucide-react";
import { useState } from "react";

import { useFeedback } from "@/components/feedback";
import { PhoneField } from "@/components/phone-field";
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
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import { formatDocument } from "@/lib/documents";
import { formatPhone } from "@/lib/phones";
import type { Party } from "@/lib/types";

export default function PartiesPage() {
  const { orgId } = useOrg();
  const { confirm, notify } = useFeedback();
  const [kind, setKind] = useState<"customer" | "supplier">("customer");
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<Party | null>(null);

  const parties = useQuery({
    queryKey: ["parties", orgId, kind],
    queryFn: () => api<Party[]>(`/v1/parties?kind=${kind}`, { orgId }),
    enabled: !!orgId,
  });

  async function handleDelete(party: Party) {
    if (
      !(await confirm(
        `¿Eliminar "${party.name}"? Esta acción no se puede deshacer.`,
      ))
    )
      return;
    try {
      await api(`/v1/parties/${party.id}`, { method: "DELETE", orgId });
      parties.refetch();
    } catch (err) {
      notify(err instanceof Error ? err.message : "No se pudo eliminar");
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">
          Clientes y proveedores
        </h1>
        <Button
          onClick={() => {
            setEditing(null);
            setOpen(true);
          }}
        >
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
              kind === option
                ? "bg-primary text-white"
                : "bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 border border-slate-300 dark:border-slate-600"
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
          <ErrorState
            message={parties.error.message}
            onRetry={() => parties.refetch()}
          />
        ) : parties.data?.length === 0 ? (
          <EmptyState message="Sin registros." />
        ) : (
          <Table headers={["Nombre", "Documento", "Teléfono", "Correo", ""]}>
            {parties.data?.map((party) => (
              <tr key={party.id}>
                <td className="px-5 py-3 font-medium">{party.name}</td>
                <td className="px-5 py-3 text-slate-600 dark:text-slate-400">
                  {party.document_id
                    ? formatDocument(party.document_type, party.document_id)
                    : ""}
                </td>
                <td className="px-5 py-3">{party.phone}</td>
                <td className="px-5 py-3">{party.email}</td>
                <td className="px-5 py-3">
                  <div className="flex justify-end gap-1">
                    <Button
                      variant="ghost"
                      className="px-2 py-1"
                      onClick={() => {
                        setEditing(party);
                        setOpen(true);
                      }}
                      aria-label="Editar"
                    >
                      <Pencil className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      className="px-2 py-1 text-red-600"
                      onClick={() => handleDelete(party)}
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
        <PartyModal
          kind={kind}
          party={editing}
          onClose={() => setOpen(false)}
          onSaved={() => {
            setOpen(false);
            setEditing(null);
            parties.refetch();
          }}
        />
      )}
    </div>
  );
}

function PartyModal({
  kind,
  party,
  onClose,
  onSaved,
}: {
  kind: "customer" | "supplier";
  party: Party | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { orgId } = useOrg();
  const [name, setName] = useState(party?.name ?? "");
  const [documentType, setDocumentType] = useState(
    party?.document_type ?? "rif",
  );
  const [documentId, setDocumentId] = useState(
    party?.document_id
      ? formatDocument(party.document_type, party.document_id)
      : "",
  );
  const [phone, setPhone] = useState(party?.phone ?? "");
  const [email, setEmail] = useState(party?.email ?? "");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const body = {
        name,
        document_type: documentType,
        document_id: formatDocument(documentType, documentId) || null,
        phone: phone ? formatPhone(phone) : null,
        email: email || null,
        is_customer: kind === "customer",
        is_supplier: kind === "supplier",
      };
      if (party) {
        await api(`/v1/parties/${party.id}`, { method: "PATCH", orgId, body });
      } else {
        await api("/v1/parties", { method: "POST", orgId, body });
      }
      onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo guardar");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <form
        onSubmit={handleSubmit}
        className="mt-16 w-full max-w-lg rounded-xl bg-white dark:bg-slate-800 shadow-lg"
      >
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
            {party ? "Editar" : "Nuevo"}{" "}
            {kind === "customer" ? "cliente" : "proveedor"}
          </h2>
        </div>
        <div className="space-y-4 px-6 py-5">
          <Field label="Nombre">
            <Input
              required
              value={name}
              onChange={(event) => setName(event.target.value)}
            />
          </Field>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label="Tipo de documento">
              <Select
                value={documentType}
                onChange={(event) => setDocumentType(event.target.value)}
              >
                <option value="rif">RIF</option>
                <option value="ci">Cédula</option>
                <option value="passport">Pasaporte</option>
                <option value="other">Otro</option>
              </Select>
            </Field>
            <Field label="Número">
              <Input
                value={documentId}
                onChange={(event) =>
                  setDocumentId(
                    formatDocument(documentType, event.target.value),
                  )
                }
                placeholder={
                  documentType === "ci"
                    ? "V-12.345.678"
                    : documentType === "rif"
                      ? "J-12345678-9"
                      : documentType === "passport"
                        ? "E-123456789"
                        : ""
                }
              />
            </Field>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <PhoneField value={phone} onChange={setPhone} />
            <Field label="Correo">
              <Input
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
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
