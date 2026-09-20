"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Button, Card, Field, Input, Select } from "@/components/ui";
import { Logo } from "@/components/logo";
import { createClient } from "@/lib/supabase/client";

export default function OnboardingPage() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [legalName, setLegalName] = useState("");
  const [taxId, setTaxId] = useState("");
  const [currency, setCurrency] = useState("VES");
  const [branchName, setBranchName] = useState("Principal");
  const [warehouseName, setWarehouseName] = useState("Almacén principal");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    const supabase = createClient();
    const { data: sessionData } = await supabase.auth.getSession();
    const userId = sessionData.session?.user.id;
    if (!userId) {
      setError("Sesión no válida.");
      setLoading(false);
      return;
    }

    const { data: org, error: orgError } = await supabase
      .from("organizations")
      .insert({
        name,
        legal_name: legalName || null,
        tax_id: taxId || null,
        default_currency: currency,
        created_by: userId,
      })
      .select("id")
      .single();
    if (orgError) {
      setError(orgError.message);
      setLoading(false);
      return;
    }

    const { data: permissions, error: permissionsError } = await supabase
      .from("permissions")
      .select("code");
    if (permissionsError) {
      setError(permissionsError.message);
      setLoading(false);
      return;
    }

    const { data: role, error: roleError } = await supabase
      .from("org_roles")
      .insert({
        org_id: org.id,
        name: "Administrador",
        permissions: permissions.map((p: { code: string }) => p.code),
        is_system: true,
      })
      .select("id")
      .single();
    if (roleError) {
      setError(roleError.message);
      setLoading(false);
      return;
    }

    const { error: memberError } = await supabase.from("memberships").insert({
      org_id: org.id,
      user_id: userId,
      role_id: role.id,
    });
    if (memberError) {
      setError(memberError.message);
      setLoading(false);
      return;
    }

    const { data: branch, error: branchError } = await supabase
      .from("branches")
      .insert({ org_id: org.id, name: branchName, code: "PRIN" })
      .select("id")
      .single();
    if (branchError) {
      setError(branchError.message);
      setLoading(false);
      return;
    }

    const { error: warehouseError } = await supabase.from("warehouses").insert({
      org_id: org.id,
      branch_id: branch.id,
      name: warehouseName,
      code: "ALM01",
    });
    if (warehouseError) {
      setError(warehouseError.message);
      setLoading(false);
      return;
    }

    window.localStorage.setItem("cresko.active-org", org.id);
    router.push("/pos");
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface dark:bg-slate-900 p-4">
      <Card className="w-full max-w-lg">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-5">
          <div className="flex items-center gap-3">
            <Logo className="h-10 w-10" />
            <div>
              <h1 className="text-xl font-semibold text-slate-900 dark:text-slate-100">Configura tu comercio</h1>
              <p className="text-sm text-slate-500 dark:text-slate-400">Crea la organización y su sucursal inicial</p>
            </div>
          </div>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4 px-6 py-5">
          <Field label="Nombre del comercio">
            <Input required value={name} onChange={(event) => setName(event.target.value)} />
          </Field>
          <div className="grid grid-cols-2 gap-4">
            <Field label="Razón social">
              <Input value={legalName} onChange={(event) => setLegalName(event.target.value)} />
            </Field>
            <Field label="RIF">
              <Input value={taxId} onChange={(event) => setTaxId(event.target.value)} />
            </Field>
          </div>
          <Field label="Moneda por defecto">
            <Select value={currency} onChange={(event) => setCurrency(event.target.value)}>
              <option value="VES">Bolívares (VES)</option>
              <option value="USD">Dólares (USD)</option>
            </Select>
          </Field>
          <div className="grid grid-cols-2 gap-4">
            <Field label="Sucursal">
              <Input required value={branchName} onChange={(event) => setBranchName(event.target.value)} />
            </Field>
            <Field label="Almacén">
              <Input required value={warehouseName} onChange={(event) => setWarehouseName(event.target.value)} />
            </Field>
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <Button type="submit" disabled={loading} className="w-full">
            {loading ? "Creando..." : "Crear comercio"}
          </Button>
        </form>
      </Card>
    </div>
  );
}