"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Button, Card, Field, Input } from "@/components/ui";
import { Logo } from "@/components/logo";
import { createClient } from "@/lib/supabase/client";

export default function SignupPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    const supabase = createClient();
    const { data, error } = await supabase.auth.signUp({ email, password });
    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }
    if (data.session) {
      router.push("/onboarding");
    } else {
      setError("Revisa tu correo para confirmar la cuenta antes de continuar.");
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface dark:bg-slate-900 p-4">
      <Card className="w-full max-w-sm">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-5">
          <div className="flex items-center gap-3">
            <Logo className="h-10 w-10" />
            <div>
              <h1 className="text-xl font-semibold text-slate-900 dark:text-slate-100">Crear cuenta</h1>
              <p className="text-sm text-slate-500 dark:text-slate-400">Comienza a usar Cresko</p>
            </div>
          </div>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4 px-6 py-5">
          <Field label="Correo electrónico">
            <Input
              type="email"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
          </Field>
          <Field label="Contraseña">
            <Input
              type="password"
              required
              minLength={8}
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </Field>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <Button type="submit" disabled={loading} className="w-full">
            {loading ? "Creando..." : "Crear cuenta"}
          </Button>
        </form>
        <div className="border-t border-slate-200 dark:border-slate-700 px-6 py-4 text-center text-sm">
          ¿Ya tienes cuenta?{" "}
          <a href="/login" className="font-medium text-primary hover:underline">
            Iniciar sesión
          </a>
        </div>
      </Card>
    </div>
  );
}