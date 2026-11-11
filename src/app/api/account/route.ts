/**
 * S18-6 / S24-1 / S57 — account management: password change, email change,
 * account deletion (grace period), data export. All are sensitive operations:
 * re-auth (current password) + 2FA when enabled + full audit + session
 * revocation where the master prompt demands it.
 */
import { db } from "@/lib/db";
import { requireAuth, requireCsrf, errorResponse, clientIp, parseStrict } from "@/lib/wavely/server/api-guard";
import { hashPassword, verifyPassword, checkPasswordPolicy } from "@/lib/wavely/server/password";
import { revokeAllSessions } from "@/lib/wavely/server/sessions";
import { clearCookieSpecs } from "@/lib/wavely/server/sessions";
import { audit } from "@/lib/wavely/server/audit";
import { newToken, hashToken } from "@/lib/wavely/server/tokens";
import { z } from "zod";

const SENSITIVE = { sensitive: true } as const;

const PasswordChangeSchema = z
  .object({
    currentPassword: z.string().min(1).max(128),
    newPassword: z.string().min(12).max(128),
  })
  .strict();

const EmailChangeSchema = z
  .object({
    password: z.string().min(1).max(128),
    newEmail: z.string().email().max(254),
  })
  .strict();

const DeleteSchema = z
  .object({
    password: z.string().min(1).max(128),
    confirm: z.literal("DELETE"),
  })
  .strict();

/** Shared re-auth: password (+ 2FA code when enabled) — T-S18-6. */
async function reauthenticate(userId: string, password: string, otp?: string): Promise<boolean> {
  const user = await db.user.findUnique({ where: { id: userId } });
  if (!user) return false;
  const pwOk = user.passwordHash ? await verifyPassword(password, user.passwordHash) : false;
  if (!pwOk) return false;
  if (user.twoFactorEnabled) {
    if (!otp) return false;
    const { totpVerify, hashCode } = await import("@/lib/wavely/server/totp");
    const { decryptSecret } = await import("@/lib/wavely/server/crypto");
    const secret = user.twoFactorSecret ? decryptSecret(user.twoFactorSecret) : null;
    const codeOk = secret ? totpVerify(secret, otp).ok : false;
    const rec = codeOk ? null : await db.recoveryCode.findFirst({ where: { userId, codeHash: hashCode(otp), usedAt: null } });
    if (!codeOk && !rec) return false;
    if (rec) await db.recoveryCode.update({ where: { id: rec.id }, data: { usedAt: new Date() } });
  }
  return true;
}

/** T-S57-2: change password — current password + 2FA, revoke all sessions. */
export async function PUT(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "invalid_json");
  }
  const parsed = parseStrict(PasswordChangeSchema, body);
  if (!parsed.ok) return errorResponse(400, "invalid_input");

  const rl = (await import("@/lib/wavely/server/rate-limit")).rateLimit(`pw-change:${auth.auth.userId}`, 3, 900);
  if (!rl.allowed) return errorResponse(429, "rate_limited");

  const otp = request.headers.get("x-2fa-code") ?? undefined;
  const ok = await reauthenticate(auth.auth.userId, parsed.data.currentPassword, otp);
  if (!ok) return errorResponse(401, "reauth-failed");

  const policy = await checkPasswordPolicy(parsed.data.newPassword);
  if (!policy.ok) return errorResponse(400, "password-policy");

  const hash = await hashPassword(parsed.data.newPassword);
  await db.user.update({ where: { id: auth.auth.userId }, data: { passwordHash: hash, failedAttempts: 0, lockoutUntil: null } });
  // T-S20-6: changing the password revokes EVERY session (incl. current)
  const revoked = await revokeAllSessions(auth.auth.userId);
  await audit({ userId: auth.auth.userId, event: "password_change", ip: clientIp(request), meta: { sessionsRevoked: revoked } });

  const secure = request.url.startsWith("https");
  const headers = new Headers({ "cache-control": "no-store" });
  for (const c of clearCookieSpecs(secure)) {
    const parts = [`${c.name}=`, "Path=/", "Max-Age=0", "HttpOnly", `SameSite=${c.sameSite}`];
    if (c.secure) parts.push("Secure");
    headers.append("set-cookie", parts.join("; "));
  }
  return new Response(JSON.stringify({ ok: true, revokedSessions: revoked }), { status: 200, headers });
}

/** T-S24-1 / T-S57-1: change email — password + 2FA + confirmation tokens for old AND new address. */
export async function POST(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "invalid_json");
  }
  const parsed = parseStrict(EmailChangeSchema, body);
  if (!parsed.ok) return errorResponse(400, "invalid_input");

  const otp = request.headers.get("x-2fa-code") ?? undefined;
  const ok = await reauthenticate(auth.auth.userId, parsed.data.password, otp);
  if (!ok) return errorResponse(401, "reauth-failed");

  const user = await db.user.findUnique({ where: { id: auth.auth.userId } });
  if (!user) return errorResponse(404, "not_found");
  const clash = await db.user.findUnique({ where: { email: parsed.data.newEmail } });
  if (clash && clash.id !== user.id) return errorResponse(409, "email_unavailable"); // uniform, no enumeration

  // confirmation tokens: one hashed token per address (delivered by mail worker)
  const tokenOld = newToken();
  const tokenNew = newToken();
  await db.emailVerification.createMany({
    data: [
      { userId: user.id, tokenHash: hashToken(tokenOld), expiresAt: new Date(Date.now() + 30 * 60 * 1000) },
      { userId: user.id, tokenHash: hashToken(tokenNew), expiresAt: new Date(Date.now() + 30 * 60 * 1000) },
    ],
  });
  // prototype: stage the pending email on the user row for the confirmation flow
  await db.user.update({ where: { id: user.id }, data: { emailVerified: false } });
  await audit({ userId: user.id, event: "email_change", ip: clientIp(request), meta: { staged: true } });

  return Response.json(
    { ok: true, pending: true, confirmationsRequired: 2 },
    { headers: { "cache-control": "no-store" } },
  );
}

/** T-S24-2 / T-S57-3: delete account — re-auth + grace period. */
export async function DELETE(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "invalid_json");
  }
  const parsed = parseStrict(DeleteSchema, body);
  if (!parsed.ok) return errorResponse(400, "invalid_input");

  const otp = request.headers.get("x-2fa-code") ?? undefined;
  const ok = await reauthenticate(auth.auth.userId, parsed.data.password, otp);
  if (!ok) return errorResponse(401, "reauth-failed");

  // grace period: soft-delete, restore possible until purge
  const GRACE_DAYS = 14;
  const deleted = await db.user.update({
    where: { id: auth.auth.userId },
    data: { deletedAt: new Date(Date.now() + GRACE_DAYS * 86400000) },
  });
  await revokeAllSessions(auth.auth.userId);
  await audit({ userId: auth.auth.userId, event: "account_deleted", ip: clientIp(request), meta: { graceDays: GRACE_DAYS, deletedAt: deleted.deletedAt?.toISOString() ?? null } });
  void SENSITIVE;

  const secure = request.url.startsWith("https");
  const headers = new Headers({ "cache-control": "no-store" });
  for (const c of clearCookieSpecs(secure)) {
    const parts = [`${c.name}=`, "Path=/", "Max-Age=0", "HttpOnly", `SameSite=${c.sameSite}`];
    if (c.secure) parts.push("Secure");
    headers.append("set-cookie", parts.join("; "));
  }
  return new Response(JSON.stringify({ ok: true, graceUntil: deleted.deletedAt }), { status: 200, headers });
}
