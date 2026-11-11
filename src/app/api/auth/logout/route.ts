/**
 * S20 / S66-16 — logout: revoke the current session (or ?all=1 → every
 * session), full cookie cleanup (max-age=0), audit log.
 */
import { db } from "@/lib/db";
import { requireAuth, errorResponse, clientIp } from "@/lib/wavely/server/api-guard";
import { clearCookieSpecs } from "@/lib/wavely/server/sessions";
import { audit } from "@/lib/wavely/server/audit";

function cleanupHeaders(secure: boolean): Headers {
  const headers = new Headers({ "cache-control": "no-store" });
  for (const c of clearCookieSpecs(secure)) {
    const parts = [`${c.name}=`, "Path=/", "Max-Age=0", "HttpOnly", `SameSite=${c.sameSite}`];
    if (c.secure) parts.push("Secure");
    headers.append("set-cookie", parts.join("; "));
  }
  return headers;
}

export async function POST(request: Request) {
  const auth = await requireAuth(request);
  const secure = request.url.startsWith("https");
  if (!auth.ok || !auth.auth) {
    // clearing cookies anyway — a stale session must die client-side too
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: cleanupHeaders(secure) });
  }
  await db.session.update({ where: { id: auth.auth.sessionId }, data: { revokedAt: new Date() } }).catch(() => undefined);
  await audit({ userId: auth.auth.userId, event: "logout", ip: clientIp(request) });
  return new Response(JSON.stringify({ ok: true }), { status: 200, headers: cleanupHeaders(secure) });
}

export async function DELETE(request: Request) {
  // sign out of ALL devices
  const auth = await requireAuth(request);
  const secure = request.url.startsWith("https");
  if (!auth.ok || !auth.auth) {
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: cleanupHeaders(secure) });
  }
  const rows = await db.session.updateMany({ where: { userId: auth.auth.userId, revokedAt: null }, data: { revokedAt: new Date() } });
  await audit({ userId: auth.auth.userId, event: "sessions_revoked_all", ip: clientIp(request) });
  return new Response(JSON.stringify({ ok: true, revoked: rows.count }), { status: 200, headers: cleanupHeaders(secure) });
}
