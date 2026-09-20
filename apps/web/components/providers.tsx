"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";

import { api } from "@/lib/api";
import { ThemeProvider } from "@/components/theme-provider";
import type { CurrentUser, Organization, Permission } from "@/lib/types";

type OrgContextValue = {
  memberships: CurrentUser["memberships"];
  orgId: string | null;
  orgName: string | null;
  roleName: string | null;
  permissions: Permission[];
  loading: boolean;
  setOrgId: (orgId: string) => void;
  refreshOrg: () => void;
  can: (permission: Permission) => boolean;
};

const OrgContext = createContext<OrgContextValue | null>(null);

const ORG_KEY = "cresko.active-org";

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider>
        <OrgProvider>{children}</OrgProvider>
      </ThemeProvider>
    </QueryClientProvider>
  );
}

function OrgProvider({ children }: { children: React.ReactNode }) {
  const [memberships, setMemberships] = useState<CurrentUser["memberships"]>([]);
  const [orgId, setOrgIdState] = useState<string | null>(null);
  const [orgName, setOrgName] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const loadOrg = useCallback((nextOrgId: string | null) => {
    if (!nextOrgId) {
      setOrgName(null);
      return;
    }
    api<Organization>("/v1/orgs", { orgId: nextOrgId })
      .then((org) => setOrgName(org.name))
      .catch(() => setOrgName(null));
  }, []);

  useEffect(() => {
    const stored = window.localStorage.getItem(ORG_KEY);
    if (stored) setOrgIdState(stored);
    api<CurrentUser>("/v1/me")
      .then((me) => {
        setMemberships(me.memberships);
        const active = me.memberships.find((m) => m.org_id === stored)?.org_id
          ?? me.memberships[0]?.org_id
          ?? null;
        setOrgIdState(active);
        if (active) window.localStorage.setItem(ORG_KEY, active);
        loadOrg(active);
      })
      .catch(() => {
        setMemberships([]);
      })
      .finally(() => setLoading(false));
  }, [loadOrg]);

  const setOrgId = (next: string) => {
    setOrgIdState(next);
    window.localStorage.setItem(ORG_KEY, next);
    loadOrg(next);
  };

  const refreshOrg = () => loadOrg(orgId);

  const activeMembership = memberships.find((m) => m.org_id === orgId) ?? null;
  const roleName = activeMembership?.role_name ?? null;
  const permissions = activeMembership?.permissions ?? [];

  const can = useCallback((permission: Permission) => permissions.includes(permission), [permissions]);

  const value = useMemo(
    () => ({ memberships, orgId, orgName, roleName, permissions, loading, setOrgId, refreshOrg, can }),
    [memberships, orgId, orgName, roleName, permissions, loading, can, refreshOrg],
  );

  return <OrgContext.Provider value={value}>{children}</OrgContext.Provider>;
}

export function useOrg() {
  const ctx = useContext(OrgContext);
  if (!ctx) throw new Error("useOrg must be used within Providers");
  return ctx;
}