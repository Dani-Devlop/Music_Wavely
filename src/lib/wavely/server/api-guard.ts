/**
 * S45 / S56 — access control + API guard:
 * - ownership checks (IDOR/BOLA defence)
 * - role model (user/premium/admin), server-side only, revalidation on
 *   sensitive ops
 * - uniform error envelopes without stack traces
 * - strict body validation via Zod (rejects unknown fields — S48-4)
 */
import { z } from "zod";
import { db } from "@/lib/db";
import { resolveSession, type CookieSpec } from "./sessions";
import { verifyCsrf } from "./csrf";
import { checkRate, type RateVerdict } from "./rate-limit";
import { audit } from "./audit";

export type Role = "user" | "premium" | "admin";

export interface AuthContext {
  sessionId: string;
  userId: string;
  role: Role;
}

export interface GuardResult {
  ok: boolean;
  status: number;
  code: string;
  message?: string;
  auth?: AuthContext;
  cookies?: CookieSpec[];
}

/** Extract host for CSRF Origin checks. */
function requestHost(request: Request): string {
  return request.headers.get("host") ?? "localhost:3000";
}

export function clientIp(request: Request): string {
  const fwd = request.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0].trim();
  return request.headers.get("x-real-ip") ?? "127.0.0.1";
}

/** T-S56-1: authenticate from the HttpOnly session cookie. */
export async function requireAuth(request: Request): Promise<GuardResult> {
  const cookieName = request.url.startsWith("https") ? "__Host-wavely_session" : "wavely_session";
  const raw = request.headers.get("cookie") ?? "";
  let token: string | null = null;
  for (const part of raw.split(";")) {
    const i = part.indexOf("=");
    if (i > 0 && part.slice(0, i).trim() === cookieName) token = decodeURIComponent(part.slice(i + 1).trim());
  }
  const session = await resolveSession(token);
  if (!session) return { ok: false, status: 401, code: "unauthorized" };
  const user = await db.user.findUnique({ where: { id: session.userId }, select: { id: true, role: true, deletedAt: true } });
  if (!user || user.deletedAt) return { ok: false, status: 401, code: "unauthorized" };
  return { ok: true, status: 200, code: "ok", auth: { sessionId: session.sessionId, userId: user.id, role: user.role as Role } };
}

/** CSRF gate for mutations (T-S42-4). */
export async function requireCsrf(request: Request, sessionId: string | null): Promise<GuardResult> {
  const verdict = await verifyCsrf(request, sessionId, requestHost(request));
  if (verdict.ok) return { ok: true, status: 200, code: "ok" };
  return { ok: false, status: verdict.code, code: `csrf-${verdict.reason}` };
}

/** T-S45-4: role from server record only; revalidated per request. */
export async function requireRole(request: Request, role: Role): Promise<GuardResult> {
  const base = await requireAuth(request);
  if (!base.ok || !base.auth) return base;
  const order: Record<Role, number> = { user: 0, premium: 1, admin: 2 };
  const user = await db.user.findUnique({ where: { id: base.auth.userId }, select: { role: true } });
  if (!user || order[user.role as Role] < order[role]) return { ok: false, status: 403, code: "forbidden" };
  return base;
}

/** T-S46-x: rate-limit wrapper. */
export function guardRate(request: Request, kind: Parameters<typeof checkRate>[0], userId: string | null): GuardResult {
  const verdict: RateVerdict = checkRate(kind, clientIp(request), userId, new URL(request.url).pathname);
  if (verdict.allowed) return { ok: true, status: 200, code: "ok" };
  return { ok: false, status: 429, code: "rate_limited", message: String(verdict.retryAfter) };
}

/** T-S45-1: ownership check — resource must belong to the caller. */
export function assertOwnership<T extends { userId: string }>(resource: T | null, userId: string, code = "not_found"): GuardResult {
  if (!resource) return { ok: false, status: 404, code }; // 404, not 403 → no resource existence leak
  if (resource.userId !== userId) return { ok: false, status: 404, code };
  return { ok: true, status: 200, code: "ok" };
}

// ── Error envelope (T-S56-4/5): proper codes, never a stack trace ────────────

export function errorResponse(status: number, code: string, message?: string): Response {
  return Response.json({ ok: false, error: { code, message: message ?? undefined } }, { status });
}

export function okResponse<T extends object>(data: T, cookies?: CookieSpec[]): Response {
  const res = Response.json({ ok: true, ...data });
  if (cookies) {
    const headers = new Headers(res.headers);
    const setCookies = cookies.map((c) => {
      const parts = [`${c.name}=${encodeURIComponent(c.value)}`, `Path=${c.path}`, `Max-Age=${c.maxAge}`, "HttpOnly", `SameSite=${c.sameSite}`];
      if (c.secure) parts.push("Secure");
      return parts.join("; ");
    });
    headers.set("cache-control", "no-store");
    headers.delete("set-cookie");
    headers.append("set-cookie", setCookies.join(", "));
    return new Response(res.body, { status: res.status, headers });
  }
  const headers = new Headers(res.headers);
  headers.set("cache-control", "no-store");
  return new Response(res.body, { status: res.status, headers });
}

/**
 * T-S48-4 / T-S56-6: strict Zod parsing — unknown fields rejected, so clients
 * cannot mass-assign columns.
 */
export function parseStrict<S extends z.ZodTypeAny>(schema: S, input: unknown): { ok: true; data: z.infer<S> } | { ok: false; status: number; code: string } {
  const parsed = schema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, status: 400, code: "invalid_input" };
  }
  return { ok: true, data: parsed.data };
}

export async function auditOrThrow(userId: string | null, event: Parameters<typeof audit>[0]["event"], request: Request, meta?: Record<string, string | number | boolean | null>) {
  await audit({
    userId,
    event,
    ip: clientIp(request),
    userAgent: request.headers.get("user-agent"),
    meta,
  });
}
