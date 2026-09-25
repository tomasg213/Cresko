import { createClient } from "@/lib/supabase";

export type AdminOrg = {
  org_id: string;
  org_name: string;
  owner_email: string;
  owner_name: string;
  created_at: string;
  member_count: number;
  access_status: "active" | "suspended";
  payment_status: "paid" | "free" | "pending";
  notes: string | null;
};

export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

export async function api<T>(
  path: string,
  options: { method?: string; body?: unknown; orgId?: string | null } = {},
): Promise<T> {
  const supabase = createClient();
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new ApiError("Sesión no válida", 401);

  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
  if (options.orgId) headers["X-Org-ID"] = options.orgId;

  const response = await fetch(`${API_URL}${path}`, {
    method: options.method ?? "GET",
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });

  if (!response.ok) {
    let detail = response.statusText;
    try {
      const payload = await response.json();
      detail =
        typeof payload.detail === "string"
          ? payload.detail
          : JSON.stringify(payload);
    } catch {
      // keep default
    }
    throw new ApiError(detail, response.status);
  }
  if (response.status === 204) return undefined as T;
  return response.json() as Promise<T>;
}

export const API_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "https://cresko.vercel.app/api";