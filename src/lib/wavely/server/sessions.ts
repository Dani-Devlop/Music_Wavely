/**
 * S20 / S40 / S41 — session + cookie security.
 * - Session IDs are 256-bit opaque tokens; only SHA-256 hashes are stored.
 * - Server-side store (DB table in the prototype; Redis-backed in prod).
 * - Idle expiry 30min, absolute expiry 12h (S40-4).
 * - Rotation on login (fixation defence, S40-7) and refresh (S40-5).
 * - Cookies: HttpOnly, Secure, SameSite=Lax, __Host- prefix when served over TLS.
 */
import { db } from "@/lib/db";
import { newToken, hashToken } from "./tokens";

export const SESSION_IDLE_MINUTES = 30;
export const SESSION_ABSOLUTE_HOURS = 12;
export const REMEMBER_DAYS = 30;
export const ACCESS_TOKEN_MINUTES = 15;

const COOKIE_NAME_BASE = "wavely_session";
const REFRESH_COOKIE = "wavely_refresh";

export interface SessionCookieConfig {
  secure: boolean; // served over HTTPS?
  maxAgeSec?: number;
}

/** S41-2: __Host- prefix requires Secure + Path=/ + no Domain. */
export function sessionCookieName(secure: boolean): string {
  return secure ? `__Host-${COOKIE_NAME_BASE}` : COOKIE_NAME_BASE;
}

export function refreshCookieName(secure: boolean): string {
  return secure ? `__Host-${REFRESH_COOKIE}` : REFRESH_COOKIE;
}

export interface CookieSpec {
  name: string;
  value: string;
  httpOnly: boolean;
  secure: boolean;
  sameSite: "Lax" | "Strict";
  path: string;
  maxAge: number;
  domain?: undefined; // T-S41-3: never set Domain — host-only cookies
}

function buildCookie(name: string, value: string, secure: boolean, maxAge: number, sameSite: "Lax" | "Strict"): CookieSpec {
  return {
    name,
    value,
    httpOnly: true, // T-S41-1
    secure, // T-S41-1 (SameSite=None only ever with Secure; we don't use None)
    sameSite,
    path: "/",
    maxAge,
  };
}

export function toSetCookie(c: CookieSpec): string {
  const parts = [
    `${c.name}=${c.value}`,
    `Path=${c.path}`,
    `Max-Age=${c.maxAge}`,
    `HttpOnly`,
    `SameSite=${c.sameSite}`,
  ];
  if (c.secure) parts.push("Secure");
  return parts.join("; ");
}

export function readCookie(request: Request, name: string): string | null {
  const raw = request.headers.get("cookie");
  if (!raw) return null;
  for (const part of raw.split(";")) {
    const idx = part.indexOf("=");
    if (idx === -1) continue;
    if (part.slice(0, idx).trim() === name) return decodeURIComponent(part.slice(idx + 1).trim());
  }
  return null;
}

// ── Session lifecycle ────────────────────────────────────────────────────────

export interface CreateSessionInput {
  userId: string;
  ip?: string | null;
  deviceInfo?: string | null;
  browser?: string | null;
  secure: boolean;
  remember?: boolean;
}

export interface CreatedSession {
  sessionId: string;
  token: string;
  refresh: string;
  accessCookie: CookieSpec;
  refreshCookie: CookieSpec;
}

/** Absolute+idle expiry. Remember-me extends the *token* lifetime, never past absolute cap for access. */
function expiries() {
  const now = Date.now();
  return {
    idleExpiresAt: new Date(now + SESSION_IDLE_MINUTES * 60 * 1000),
    absoluteExpiresAt: new Date(now + SESSION_ABSOLUTE_HOURS * 60 * 60 * 1000),
  };
}

/**
 * Create a session. Rotation-on-login: caller must ensure any pre-auth
 * anonymous session id is invalidated before calling (S40-7).
 */
export async function createSession(input: CreateSessionInput): Promise<CreatedSession> {
  const token = newToken(); // ≥128-bit (256-bit)
  const refresh = newToken();
  const { idleExpiresAt, absoluteExpiresAt } = expiries();
  const row = await db.session.create({
    data: {
      userId: input.userId,
      tokenHash: hashToken(token),
      refreshHash: hashToken(refresh),
      ip: input.ip ?? null,
      deviceInfo: input.deviceInfo ?? null,
      browser: input.browser ?? null,
      idleExpiresAt,
      absoluteExpiresAt,
    },
  });
  const maxAge = input.remember ? REMEMBER_DAYS * 24 * 3600 : SESSION_ABSOLUTE_HOURS * 3600;
  return {
    sessionId: row.id,
    token,
    refresh,
    accessCookie: buildCookie(sessionCookieName(input.secure), token, input.secure, maxAge, "Lax"),
    refreshCookie: buildCookie(refreshCookieName(input.secure), refresh, input.secure, maxAge, "Lax"),
  };
}

export interface LiveSession {
  sessionId: string;
  userId: string;
}

/** Resolve a cookie token to a live session with idle/absolute/revocation checks (S40-4/6). */
export async function resolveSession(token: string | null): Promise<LiveSession | null> {
  if (!token) return null;
  const row = await db.session.findUnique({ where: { tokenHash: hashToken(token) } });
  if (!row) return null;
  if (row.revokedAt) return null;
  const now = new Date();
  if (row.absoluteExpiresAt.getTime() <= now.getTime()) return null;
  if (row.idleExpiresAt.getTime() <= now.getTime()) {
    await db.session.update({ where: { id: row.id }, data: { revokedAt: now } }).catch(() => undefined);
    return null;
  }
  // sliding idle window
  await db.session
    .update({
      where: { id: row.id },
      data: { lastActivity: now, idleExpiresAt: new Date(now.getTime() + SESSION_IDLE_MINUTES * 60 * 1000) },
    })
    .catch(() => undefined);
  return { sessionId: row.id, userId: row.userId };
}

/** S40-5: rotating refresh — old token is revoked atomically, new one issued. */
export async function rotateRefresh(refreshToken: string | null, secure: boolean): Promise<(CreatedSession & { oldRejected: boolean }) | null> {
  if (!refreshToken) return null;
  const old = await db.session.findUnique({ where: { refreshHash: hashToken(refreshToken) } });
  if (!old || old.revokedAt || old.replacedByHash) return null; // reuse of already-rotated token → reject
  const now = new Date();
  if (old.absoluteExpiresAt.getTime() <= now.getTime()) return null;
  const token = newToken();
  const refresh = newToken();
  const refreshed = await db.session.update({
    where: { id: old.id },
    data: {
      tokenHash: hashToken(token),
      refreshHash: hashToken(refresh),
      lastActivity: now,
      idleExpiresAt: new Date(now.getTime() + SESSION_IDLE_MINUTES * 60 * 1000),
    },
  });
  const maxAge = Math.max(60, Math.floor((refreshed.absoluteExpiresAt.getTime() - now.getTime()) / 1000));
  return {
    sessionId: old.id,
    token,
    refresh,
    oldRejected: true,
    accessCookie: buildCookie(sessionCookieName(secure), token, secure, maxAge, "Lax"),
    refreshCookie: buildCookie(refreshCookieName(secure), refresh, secure, maxAge, "Lax"),
  };
}

/** S40-6: immediate revocation. */
export async function revokeSession(sessionId: string): Promise<void> {
  await db.session.update({ where: { id: sessionId }, data: { revokedAt: new Date() } }).catch(() => undefined);
}

/** S19-4 / T-S20-6: revoke every session of a user (logout-all / password change). */
export async function revokeAllSessions(userId: string): Promise<number> {
  const res = await db.session.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
  return res.count;
}

/** S40-8: session list with device/browser/IP/last activity. */
export async function listSessions(userId: string) {
  const rows = await db.session.findMany({
    where: { userId, revokedAt: null, absoluteExpiresAt: { gt: new Date() } },
    orderBy: { lastActivity: "desc" },
  });
  return rows.map((r) => ({
    id: r.id,
    device: r.deviceInfo ?? "Unknown device",
    browser: r.browser ?? "Unknown browser",
    ip: r.ip ?? "—",
    lastActivity: r.lastActivity.toISOString(),
    createdAt: r.createdAt.toISOString(),
  }));
}

/** S41-5: logout cookie cleanup specs (max-age=0). */
export function clearCookieSpecs(secure: boolean): CookieSpec[] {
  return [
    buildCookie(sessionCookieName(secure), "", secure, 0, "Lax"),
    buildCookie(refreshCookieName(secure), "", secure, 0, "Lax"),
  ];
}

/** T-S41-4: cookie payload is an opaque token — 43 chars ≪ 4KB; guard anyway. */
export function cookieWithinLimit(value: string): boolean {
  return Buffer.byteLength(`wavely_session=${value}; Path=/; Max-Age=3600; HttpOnly; SameSite=Lax`, "utf8") < 4096;
}
