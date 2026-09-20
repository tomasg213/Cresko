"use client";

import { Menu, Moon, Sun } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { Logo } from "@/components/logo";
import { Sidebar } from "@/components/sidebar";
import { useOrg } from "@/components/providers";
import { useTheme } from "@/components/theme-provider";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { orgId, loading } = useOrg();
  const router = useRouter();
  const [mobileOpen, setMobileOpen] = useState(false);
  const { theme, toggle } = useTheme();

  useEffect(() => {
    if (!loading && !orgId) {
      router.replace("/onboarding");
    }
  }, [loading, orgId, router]);

  return (
    <div className="flex h-screen flex-col bg-surface md:flex-row dark:bg-slate-900">
      <Sidebar mobileOpen={mobileOpen} onNavigate={() => setMobileOpen(false)} />
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between border-b border-slate-200 bg-white px-3 py-2.5 md:hidden dark:border-slate-700 dark:bg-slate-900">
          <button
            onClick={() => setMobileOpen(true)}
            aria-label="Abrir menú"
            className="rounded-lg p-2 text-slate-700 hover:bg-slate-100 dark:text-slate-200 dark:hover:bg-slate-800"
          >
            <Menu className="h-6 w-6" />
          </button>
          <Logo className="h-7 w-7" />
          <button
            onClick={toggle}
            aria-label="Cambiar tema"
            className="rounded-lg p-2 text-slate-700 hover:bg-slate-100 dark:text-slate-200 dark:hover:bg-slate-800"
          >
            {theme === "dark" ? <Sun className="h-5 w-5" /> : <Moon className="h-5 w-5" />}
          </button>
        </header>
        <main className="flex-1 overflow-y-auto p-4 sm:p-6">{children}</main>
      </div>
    </div>
  );
}