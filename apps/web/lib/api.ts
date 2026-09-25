"use client";

import { createClient } from "./supabase/client";

export class ApiError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

export const API_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "http://127.0.0.1:8000";

export type ApiOptions = {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  orgId?: string | null;
};

export async function api<T>(
  path: string,
  options: ApiOptions = {},
): Promise<T> {
  const supabase = createClient();
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) {
    throw new ApiError("Sesión no válida", 401);
  }

  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
  if (options.orgId) {
    headers["X-Org-ID"] = options.orgId;
  }

  const response = await fetch(`${API_URL}${path}`, {
    method: options.method ?? "GET",
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });

  if (response.status === 401) {
    await redirectToLogin(supabase);
  }

  if (!response.ok) {
    let detail = response.statusText;
    try {
      const payload = await response.json();
      detail =
        typeof payload.detail === "string"
          ? payload.detail
          : JSON.stringify(payload);
    } catch {
      // keep default detail
    }
    throw new ApiError(detail, response.status);
  }

  if (response.status === 204) {
    return undefined as T;
  }
  return response.json() as Promise<T>;
}

export async function redirectToLogin(
  supabase: ReturnType<typeof createClient>,
) {
  try {
    await supabase.auth.signOut();
  } catch {
    // noop
  }
  window.localStorage.removeItem("cresko.active-org");
  window.location.href = "/login";
}
