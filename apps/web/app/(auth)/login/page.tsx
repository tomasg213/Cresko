"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Button, Card, Field, Input } from "@/components/ui";
import { Logo } from "@/components/logo";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
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
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }
    router.push("/pos");
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface dark:bg-slate-900 p-4">
      <Card className="w-full max-w-sm">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-5">
          <div className="flex items-center gap-3">
            <Logo className="h-10 w-10" />
            <div>
              <h1 className="text-xl font-semibold text-slate-900 dark:text-slate-100">Cresko</h1>
              <p className="text-sm text-slate-500 dark:text-slate-400">Inicia sesión en tu comercio</p>
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
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </Field>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <Button type="submit" disabled={loading} className="w-full">
            {loading ? "Entrando..." : "Entrar"}
          </Button>
        </form>
        <div className="border-t border-slate-200 dark:border-slate-700 px-6 py-4 text-center text-sm">
          ¿No tienes cuenta?{" "}
          <a href="/signup" className="font-medium text-primary hover:underline">
            Crear cuenta
          </a>
        </div>
      </Card>
    </div>
  );
}