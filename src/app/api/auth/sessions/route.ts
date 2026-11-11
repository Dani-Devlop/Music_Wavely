/**
 * S20 / S40-8 — Session management: list live sessions, revoke one/all.
 * Sessions endpoint also issues CSRF tokens (GET /api/auth/sessions?csrf=1).
 */
import { requireAuth, requireCsrf, errorResponse, clientIp } from "@/lib/wavely/server/api-guard";
import { listSessions } from "@/lib/wavely/server/sessions";
import { issueCsrf } from "@/lib/wavely/server/csrf";
import { db } from "@/lib/db";
import { audit } from "@/lib/wavely/server/audit";

export async function GET(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const sessions = await listSessions(auth.auth.userId);
  const url = new URL(request.url);
  const headers = new Headers({ "cache-control": "no-store" });
  if (url.searchParams.get("csrf") === "1") {
    const csrf = await issueCsrf(auth.auth.sessionId);
    return Response.json({ ok: true, sessions, csrfToken: csrf.token }, { headers });
  }
  return Response.json({ ok: true, sessions }, { headers });
}

export async function DELETE(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);

  const url = new URL(request.url);
  const id = url.searchParams.get("id");
  if (id) {
    const owned = await db.session.findFirst({ where: { id, userId: auth.auth.userId } });
    if (!owned) return errorResponse(404, "not_found"); // IDOR-safe
    await db.session.update({ where: { id }, data: { revokedAt: new Date() } });
    await audit({ userId: auth.auth.userId, event: "session_revoked", ip: clientIp(request) });
    return Response.json({ ok: true, revoked: 1 }, { headers: { "cache-control": "no-store" } });
  }
  const rows = await db.session.updateMany({ where: { userId: auth.auth.userId, revokedAt: null }, data: { revokedAt: new Date() } });
  await audit({ userId: auth.auth.userId, event: "sessions_revoked_all", ip: clientIp(request) });
  return Response.json({ ok: true, revoked: rows.count }, { headers: { "cache-control": "no-store" } });
}
