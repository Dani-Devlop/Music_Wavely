/**
 * S25 / S52 / T-S25-2 — Telegram WebApp auth endpoint.
 * Validates initData server-side (HMAC-SHA-256 + replay window) and issues an
 * HttpOnly session. The response NEVER contains the bot token — only the
 * public identity + session metadata.
 */
import { db } from "@/lib/db";
import { validateInitData, publicTelegramIdentity } from "@/lib/wavely/server/telegram";
import { createSession, resolveSession, sessionCookieName, readCookie, listSessions } from "@/lib/wavely/server/sessions";
import { errorResponse, clientIp, guardRate, requireAuth } from "@/lib/wavely/server/api-guard";
import { audit } from "@/lib/wavely/server/audit";
import { issueCsrf } from "@/lib/wavely/server/csrf";

export async function POST(request: Request) {
  const rate = guardRate(request, "sensitive", null);
  if (!rate.ok) {
    const res = errorResponse(rate.status, rate.code, rate.message);
    res.headers.set("retry-after", rate.message ?? "60");
    return res;
  }

  let body: { initData?: string };
  try {
    body = (await request.json()) as { initData?: string };
  } catch {
    return errorResponse(400, "invalid_json");
  }

  const verdict = validateInitData(body.initData ?? "");
  if (!verdict.ok) {
    await audit({ event: "login_failed", ip: clientIp(request), meta: { reason: verdict.reason ?? "unknown" } });
    return errorResponse(401, "init_data_rejected"); // uniform message, no internals
  }
  const identity = publicTelegramIdentity(verdict);
  if (!identity) return errorResponse(401, "init_data_rejected");

  // Link or create the account (upsert by telegramId)
  const user = await db.user.upsert({
    where: { telegramId: identity.telegramId },
    create: {
      telegramId: identity.telegramId,
      name: identity.name,
      email: `${identity.telegramId}@telegram.wavely.local`,
      emailVerified: true,
      lastLoginAt: new Date(),
      lastLoginIp: clientIp(request),
    },
    update: { lastLoginAt: new Date(), lastLoginIp: clientIp(request) },
  });

  const secure = request.url.startsWith("https");
  const session = await createSession({
    userId: user.id,
    ip: clientIp(request),
    deviceInfo: "Telegram WebApp",
    browser: request.headers.get("user-agent")?.slice(0, 60) ?? null,
    secure,
  });
  const csrf = await issueCsrf(session.sessionId);
  await audit({ userId: user.id, event: "login", ip: clientIp(request), userAgent: request.headers.get("user-agent"), meta: { method: "telegram" } });

  const headers = new Headers({ "cache-control": "no-store" });
  const setCookie = (name: string, value: string, maxAge: number) => {
    const parts = [`${name}=${encodeURIComponent(value)}`, "Path=/", `Max-Age=${maxAge}`, "HttpOnly", "SameSite=Lax"];
    if (secure) parts.push("Secure");
    headers.append("set-cookie", parts.join("; "));
  };
  setCookie(sessionCookieName(secure), session.token, session.accessCookie.maxAge);
  setCookie("wavely_csrf", csrf.token, 3600);

  // T-S25-2 / T-S52-3: identity only — never any token material
  return new Response(
    JSON.stringify({
      ok: true,
      user: { id: user.id, name: user.name, telegramId: identity.telegramId },
      csrfToken: csrf.token,
    }),
    { status: 200, headers },
  );
}

/** GET: session list for the signed-in user. */
export async function GET(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const sessions = await listSessions(auth.auth.userId);
  return Response.json({ ok: true, sessions }, { headers: { "cache-control": "no-store" } });
}

/** DELETE: revoke one session (or ?all=1 → every session of the user). */
export async function DELETE(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const url = new URL(request.url);
  const sessionId = url.searchParams.get("id");
  if (url.searchParams.get("all") === "1") {
    const rows = await db.session.updateMany({ where: { userId: auth.auth.userId, revokedAt: null }, data: { revokedAt: new Date() } });
    await audit({ userId: auth.auth.userId, event: "sessions_revoked_all", ip: clientIp(request) });
    return Response.json({ ok: true, revoked: rows.count }, { headers: { "cache-control": "no-store" } });
  }
  if (!sessionId) return errorResponse(400, "missing_session_id");
  const owned = await db.session.findFirst({ where: { id: sessionId, userId: auth.auth.userId } });
  if (!owned) return errorResponse(404, "not_found"); // IDOR-safe: no existence leak
  await db.session.update({ where: { id: sessionId }, data: { revokedAt: new Date() } });
  await audit({ userId: auth.auth.userId, event: "session_revoked", ip: clientIp(request) });
  return Response.json({ ok: true }, { headers: { "cache-control": "no-store" } });
}
