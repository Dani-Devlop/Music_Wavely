/**
 * S39-7 / S67-6 — 2FA disable: requires password + current TOTP/recovery code
 * (re-auth). Disabling revokes nothing else but is audit logged.
 */
import { db } from "@/lib/db";
import { requireAuth, requireCsrf, errorResponse, clientIp, parseStrict } from "@/lib/wavely/server/api-guard";
import { totpVerify } from "@/lib/wavely/server/totp";
import { decryptSecret } from "@/lib/wavely/server/crypto";
import { verifyPassword } from "@/lib/wavely/server/password";
import { audit } from "@/lib/wavely/server/audit";
import { z } from "zod";

const DisableSchema = z.object({ password: z.string().min(1).max(128), code: z.string().min(6).max(14) }).strict();

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
  const parsed = parseStrict(DisableSchema, body);
  if (!parsed.ok) return errorResponse(400, "invalid_input");

  const user = await db.user.findUnique({ where: { id: auth.auth.userId } });
  if (!user) return errorResponse(404, "not_found");

  // T-S39-7: re-auth with password AND current code
  const pwOk = user.passwordHash ? await verifyPassword(parsed.data.password, user.passwordHash) : false;
  if (!pwOk) return errorResponse(401, "reauth-failed");
  const secret = user.twoFactorSecret ? decryptSecret(user.twoFactorSecret) : null;
  const codeOk = secret ? totpVerify(secret, parsed.data.code).ok : false;
  const recovery = codeOk
    ? true
    : (await db.recoveryCode.findFirst({ where: { userId: user.id, codeHash: (await import("@/lib/wavely/server/totp")).hashCode(parsed.data.code), usedAt: null } })) !== null;
  if (!codeOk && !recovery) return errorResponse(401, "reauth-failed");
  if (recovery && !codeOk) {
    const rec = await db.recoveryCode.findFirst({ where: { userId: user.id, codeHash: (await import("@/lib/wavely/server/totp")).hashCode(parsed.data.code), usedAt: null } });
    if (rec) await db.recoveryCode.update({ where: { id: rec.id }, data: { usedAt: new Date() } });
  }

  await db.user.update({ where: { id: user.id }, data: { twoFactorEnabled: false, twoFactorSecret: null } });
  await db.recoveryCode.deleteMany({ where: { userId: user.id } });
  await audit({ userId: user.id, event: "2fa_disabled", ip: clientIp(request) });
  return Response.json({ ok: true, twoFactorEnabled: false }, { headers: { "cache-control": "no-store" } });
}
