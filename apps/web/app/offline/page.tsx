"use client";

import { Logo } from "@/components/logo";

export default function OfflinePage() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-surface p-6 text-center dark:bg-slate-900">
      <Logo className="h-16 w-16" />
      <h1 className="text-xl font-semibold text-slate-900 dark:text-slate-100">Sin conexión</h1>
      <p className="max-w-sm text-sm text-slate-600 dark:text-slate-400">
        No tienes conexión a internet. Verifica tu red e intenta de nuevo. Cresko necesita conexión
        para sincronizar inventario, facturas y cuentas.
      </p>
      <button
        onClick={() => window.location.reload()}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white hover:bg-primary-dark"
      >
        Reintentar
      </button>
    </div>
  );
}