/**
 * S42 — CSRF: per-session token for every mutating (POST/PUT/PATCH/DELETE)
 * request + Origin/Referer validation. No mutation via GET.
 */
import { createHash } from "crypto";
import { db } from "@/lib/db";
import { newToken, hashToken } from "./tokens";

export interface CsrfIssue {
  token: string;
  expiresAt: Date;
}

/** Issue a CSRF token bound to a session (unique per-session, T-S42-1). */
export async function issueCsrf(sessionId: string): Promise<CsrfIssue> {
  const token = newToken(32);
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1h, rotated with session
  await db.csrfToken.create({ data: { sessionId, tokenHash: hashToken(token), expiresAt } });
  return { token, expiresAt };
}

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

export interface OriginCheck {
  ok: boolean;
  reason?: "origin" | "referer";
}

/** T-S42-2: Origin/Referer must match the host when present. */
export function checkOrigin(request: Request, host: string): OriginCheck {
  const origin = request.headers.get("origin");
  const referer = request.headers.get("referer");
  try {
    if (origin) {
      const o = new URL(origin);
      if (o.host !== host) return { ok: false, reason: "origin" };
    } else if (referer) {
      const r = new URL(referer);
      if (r.host !== host) return { ok: false, reason: "referer" };
    }
  } catch {
    return { ok: false, reason: "origin" };
  }
  return { ok: true };
}

export interface CsrfVerdict {
  ok: boolean;
  code: number;
  reason: string;
}

/**
 * Full CSRF gate for mutating requests:
 *  1. method must be mutating (GET never mutates — T-S42-3)
 *  2. Origin/Referer check
 *  3. header `x-csrf-token` must match the session's live token
 */
export async function verifyCsrf(request: Request, sessionId: string | null, host: string): Promise<CsrfVerdict> {
  const method = request.method.toUpperCase();
  if (SAFE_METHODS.has(method)) return { ok: true, code: 200, reason: "safe-method" };

  // no mutation through GET by construction
  if (method === "GET") return { ok: false, code: 405, reason: "mutation-via-get" };

  const origin = checkOrigin(request, host);
  if (!origin.ok) return { ok: false, code: 403, reason: `bad-${origin.reason}` };

  const header = request.headers.get("x-csrf-token");
  if (!sessionId || !header) return { ok: false, code: 403, reason: "missing-csrf" };

  const rows = await db.csrfToken.findMany({
    where: { sessionId, expiresAt: { gt: new Date() } },
  });
  const tokenHash = createHash("sha256").update(header).digest("hex");
  const match = rows.some((r) => r.tokenHash === tokenHash);
  if (!match) return { ok: false, code: 403, reason: "invalid-csrf" };
  return { ok: true, code: 200, reason: "ok" };
}
