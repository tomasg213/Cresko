"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";

import { Button, Card } from "@/components/ui";
import { Logo } from "@/components/logo";
import { createClient } from "@/lib/supabase/client";

export default function SuspendedPage() {
  const router = useRouter();

  useEffect(() => {
    const supabase = createClient();
    supabase.auth.getUser().then(({ data }) => {
      if (!data.user) router.replace("/login");
    });
  }, [router]);

  async function signOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.replace("/login");
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface dark:bg-slate-900 p-4">
      <Card className="w-full max-w-sm">
        <div className="border-b border-slate-200 dark:border-slate-700 px-6 py-5 text-center">
          <Logo className="mx-auto h-10 w-10" />
          <h1 className="mt-3 text-lg font-semibold text-slate-900 dark:text-slate-100">
            Cuenta suspendida
          </h1>
        </div>
        <div className="px-6 py-6">
          <p className="text-sm text-slate-600 dark:text-slate-300">
            Tu cuenta se encuentra suspendida. Comunícate con el administrador
            para regularizar tu situación.
          </p>
          <div className="mt-5">
            <Button
              type="button"
              variant="secondary"
              className="w-full"
              onClick={signOut}
            >
              Cerrar sesión
            </Button>
          </div>
        </div>
      </Card>
    </div>
  );
}
