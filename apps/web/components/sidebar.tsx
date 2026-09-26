"use client";

import {
  Archive,
  BarChart3,
  Calculator,
  ClipboardList,
  CreditCard,
  LogOut,
  Moon,
  Package,
  Settings,
  ShoppingCart,
  Store,
  Sun,
  Users,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { Logo } from "@/components/logo";
import { useOrg } from "@/components/providers";
import { useTheme } from "@/components/theme-provider";
import { redirectToLogin } from "@/lib/api";
import { createClient } from "@/lib/supabase/client";
import type { Permission } from "@/lib/types";
import { cn } from "@/lib/utils";

const NAV: {
  href: string;
  label: string;
  icon: typeof Package;
  permission: Permission;
}[] = [
  {
    href: "/pos",
    label: "Punto de venta",
    icon: ShoppingCart,
    permission: "sales.checkout",
  },
  {
    href: "/orders",
    label: "Pedidos",
    icon: ClipboardList,
    permission: "sales.checkout",
  },
  {
    href: "/cash-closes",
    label: "Cuadres de caja",
    icon: Calculator,
    permission: "sales.checkout",
  },
  {
    href: "/admin",
    label: "Administración",
    icon: Settings,
    permission: "org.manage",
  },
  {
    href: "/catalog",
    label: "Catálogo",
    icon: Package,
    permission: "catalog.read",
  },
  {
    href: "/inventory",
    label: "Inventario",
    icon: Archive,
    permission: "inventory.read",
  },
  {
    href: "/parties",
    label: "Clientes y proveedores",
    icon: Users,
    permission: "catalog.read",
  },
  {
    href: "/purchasing",
    label: "Compras",
    icon: Store,
    permission: "purchasing.read",
  },
  {
    href: "/finance",
    label: "Finanzas",
    icon: CreditCard,
    permission: "finance.read",
  },
  {
    href: "/replenishment",
    label: "Reposición",
    icon: BarChart3,
    permission: "replenishment.read",
  },
];

export function Sidebar({
  mobileOpen = false,
  onNavigate,
}: {
  mobileOpen?: boolean;
  onNavigate?: () => void;
}) {
  const pathname = usePathname();
  const { orgId, orgName, setOrgId, memberships, can } = useOrg();
  const { theme, toggle } = useTheme();

  async function signOut() {
    const supabase = createClient();
    await redirectToLogin(supabase);
  }

  const visibleNav = NAV.filter((item) => can(item.permission));
  const showSettings =
    can("org.manage") || can("members.manage") || can("roles.manage");

  const navClass = (active: boolean) =>
    cn(
      "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
      active
        ? "bg-primary text-white"
        : "text-slate-700 hover:bg-slate-100 dark:text-slate-200 dark:hover:bg-slate-800",
    );

  return (
    <>
      {mobileOpen && (
        <div
          className="fixed inset-0 z-30 bg-black/40 md:hidden"
          onClick={onNavigate}
          aria-hidden="true"
        />
      )}
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-40 flex w-64 flex-col border-r border-slate-200 bg-white transition-transform md:static md:translate-x-0 dark:border-slate-700 dark:bg-slate-900",
          mobileOpen ? "translate-x-0" : "-translate-x-full",
        )}
      >
        <div className="flex items-center gap-2 border-b border-slate-200 px-4 py-4 dark:border-slate-700">
          <Logo className="h-8 w-8" />
          <div className="min-w-0">
            <div className="text-lg font-semibold text-slate-900 dark:text-slate-100">
              Cresko
            </div>
            {orgName && (
              <div className="truncate text-xs text-slate-500 dark:text-slate-400">
                {orgName}
              </div>
            )}
          </div>
        </div>

        <nav className="flex-1 space-y-1 overflow-y-auto p-3">
          {visibleNav.map((item) => {
            const active = pathname.startsWith(item.href);
            const Icon = item.icon;
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={onNavigate}
                className={navClass(active)}
              >
                <Icon className="h-4 w-4" />
                {item.label}
              </Link>
            );
          })}
          {showSettings && (
            <Link
              href="/settings"
              onClick={onNavigate}
              className={navClass(pathname.startsWith("/settings"))}
            >
              <Settings className="h-4 w-4" />
              Configuración
            </Link>
          )}
        </nav>

        <div className="space-y-2 border-t border-slate-200 p-3 dark:border-slate-700">
          <button
            onClick={toggle}
            className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-100 dark:text-slate-200 dark:hover:bg-slate-800"
          >
            {theme === "dark" ? (
              <Sun className="h-4 w-4" />
            ) : (
              <Moon className="h-4 w-4" />
            )}
            {theme === "dark" ? "Modo claro" : "Modo oscuro"}
          </button>
          {memberships.length > 1 && (
            <label className="mb-2 block">
              <span className="mb-1 block text-xs font-medium text-slate-500 dark:text-slate-400">
                Comercio
              </span>
              <select
                value={orgId ?? ""}
                onChange={(event) => setOrgId(event.target.value)}
                className="w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
              >
                {memberships.map((m) => (
                  <option key={m.org_id} value={m.org_id}>
                    {m.org_id.slice(0, 8)}
                  </option>
                ))}
              </select>
            </label>
          )}
          <button
            onClick={signOut}
            className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-100 dark:text-slate-200 dark:hover:bg-slate-800"
          >
            <LogOut className="h-4 w-4" />
            Cerrar sesión
          </button>
        </div>
      </aside>
    </>
  );
}
