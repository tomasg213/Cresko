"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Button, Card, Field, Input } from "@/components/ui";
import { Logo } from "@/components/logo";
import { createClient } from "@/lib/supabase/client";

type ProvisionResult = {
  email: string;
  password: string;
  org_id: string;
  org_name: string;
};

export default function PreviewPage() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const response = await fetch(
        `${process.env.NEXT_PUBLIC_API_URL}/v1/preview/provision`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: name || null }),
        },
      );
      if (!response.ok) {
        let detail = "No se pudo crear el acceso de prueba.";
        try {
          const payload = await response.json();
          detail = typeof payload.detail === "string" ? payload.detail : detail;
        } catch {
          // keep default
        }
        throw new Error(detail);
      }
      const result: ProvisionResult = await response.json();

      const supabase = createClient();
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: result.email,
        password: result.password,
      });
      if (signInError) {
        throw new Error(signInError.message);
      }
      window.localStorage.setItem("cresko.active-org", result.org_id);
      router.push("/pos");
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "No se pudo crear el acceso de prueba.",
      );
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface dark:bg-slate-900 p-4">
      <div className="w-full max-w-lg space-y-6">
        <div className="text-center">
          <Logo className="mx-auto h-12 w-12" />
          <h1 className="mt-4 text-2xl font-bold text-slate-900 dark:text-slate-100">
            Prueba Cresko gratis
          </h1>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-400">
            Crea un comercio de demostración con datos de ejemplo en segundos.
            Sin tarjeta, sin correo de confirmación.
          </p>
        </div>

        <Card>
          <form onSubmit={handleSubmit} className="space-y-4 px-6 py-6">
            <Field label="Nombre de tu comercio (opcional)">
              <Input
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="Mi Comercio"
              />
            </Field>
            {error && <p className="text-sm text-red-600">{error}</p>}
            <Button type="submit" disabled={loading} className="w-full">
              {loading ? "Creando tu demo..." : "Crear comercio de prueba"}
            </Button>
          </form>
        </Card>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <FeatureCard
            title="Punto de venta"
            text="Cobra con pistola de código o cámara."
          />
          <FeatureCard
            title="Inventario"
            text="Movimientos, stock y reposición."
          />
          <FeatureCard
            title="Finanzas"
            text="CxC, CxP y cuentas por cliente."
          />
        </div>

        <p className="text-center text-xs text-slate-500 dark:text-slate-400">
          Esta es una cuenta de demostración temporal con datos ficticios.
        </p>
      </div>
    </div>
  );
}

function FeatureCard({ title, text }: { title: string; text: string }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm dark:border-slate-700 dark:bg-slate-900">
      <h3 className="text-sm font-semibold text-slate-900 dark:text-slate-100">
        {title}
      </h3>
      <p className="mt-1 text-xs text-slate-600 dark:text-slate-400">{text}</p>
    </div>
  );
}
