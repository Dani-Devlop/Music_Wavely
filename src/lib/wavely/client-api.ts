"use client";

/**
 * Client API helpers (S71): the profile is ALWAYS fetched from the server on
 * mount — never cached in localStorage, never seeded from a stale store.
 * CSRF token is issued by the session endpoints and attached to mutations.
 */

let csrfToken: string | null = null;

export function setCsrf(token: string | null) {
  csrfToken = token;
}

export function getCsrf(): string {
  return csrfToken ?? "";
}

export interface ServerProfile {
  id: string;
  name: string;
  displayName: string | null;
  email: string;
  avatar: string | null;
  language: string;
  theme: string;
  role: string;
  emailVerified: boolean;
  twoFactorEnabled: boolean;
  lastLoginAt: string | null;
  updatedAt: string;
}

export interface ServerSession {
  id: string;
  device: string;
  browser: string;
  ip: string;
  lastActivity: string;
  createdAt: string;
}

/** GET /api/profile — server truth, no-store. */
export async function fetchServerProfile(): Promise<ServerProfile | null> {
  try {
    const res = await fetch("/api/profile", { cache: "no-store" });
    if (!res.ok) return null;
    const data = (await res.json()) as { ok: boolean; profile: ServerProfile };
    return data.ok ? data.profile : null;
  } catch {
    return null;
  }
}

/** GET /api/auth/sessions — live session list + fresh CSRF token. */
export async function fetchSessions(): Promise<{ sessions: ServerSession[]; signedIn: boolean }> {
  try {
    const res = await fetch("/api/auth/sessions?csrf=1", { cache: "no-store" });
    if (res.status === 401) return { sessions: [], signedIn: false };
    if (!res.ok) return { sessions: [], signedIn: false };
    const data = (await res.json()) as { ok: boolean; sessions: ServerSession[]; csrfToken?: string };
    if (data.csrfToken) setCsrf(data.csrfToken);
    return { sessions: data.sessions, signedIn: true };
  } catch {
    return { sessions: [], signedIn: false };
  }
}

/** PUT /api/profile — atomic update with optimistic locking (x-base-updated-at). */
export async function saveServerProfile(
  patch: { name: string; email: string; avatar?: string; displayName?: string },
  baseUpdatedAt: string | null,
): Promise<{ ok: boolean; profile?: ServerProfile; conflict?: boolean }> {
  try {
    const res = await fetch("/api/profile", {
      method: "PUT",
      headers: {
        "content-type": "application/json",
        "x-csrf-token": getCsrf(),
        ...(baseUpdatedAt ? { "x-base-updated-at": baseUpdatedAt } : {}),
      },
      body: JSON.stringify({ name: patch.name, email: patch.email, ...(patch.avatar ? { avatar: patch.avatar } : {}) }),
    });
    if (res.status === 409) {
      const data = (await res.json()) as { profile?: ServerProfile };
      return { ok: false, conflict: true, profile: data.profile };
    }
    if (!res.ok) return { ok: false };
    const data = (await res.json()) as { ok: boolean; profile: ServerProfile };
    return { ok: true, profile: data.profile };
  } catch {
    return { ok: false };
  }
}
