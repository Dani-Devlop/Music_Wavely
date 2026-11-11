/**
 * S39 / S67 — 2FA verify: confirm a code against the stored secret to finish
 * setup. Severe rate limiting (5 per 5min) per user (T-S39-5).
 */
import { db } from "@/lib/db";
import { requireAuth, requireCsrf, errorResponse, clientIp, parseStrict } from "@/lib/wavely/server/api-guard";
import { totpVerify } from "@/lib/wavely/server/totp";
import { decryptSecret } from "@/lib/wavely/server/crypto";
import { rateLimit } from "@/lib/wavely/server/rate-limit";
import { audit } from "@/lib/wavely/server/audit";
import { z } from "zod";

const VerifySchema = z.object({ code: z.string().min(6).max(8) }).strict();

export async function POST(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);

  const rl = rateLimit(`2fa-verify:${auth.auth.userId}`, 5, 300); // 5 per 5min
  if (!rl.allowed) {
    const res = errorResponse(429, "rate_limited");
    res.headers.set("retry-after", String(rl.retryAfter));
    return res;
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "invalid_json");
  }
  const parsed = parseStrict(VerifySchema, body);
  if (!parsed.ok) return errorResponse(400, "invalid_code");

  const user = await db.user.findUnique({ where: { id: auth.auth.userId } });
  if (!user?.twoFactorSecret) return errorResponse(400, "no-2fa-setup");
  const secret = decryptSecret(user.twoFactorSecret);
  if (!secret) return errorResponse(500, "secret-decrypt-failed");

  const verdict = totpVerify(secret, parsed.data.code);
  if (!verdict.ok) {
    await audit({ userId: user.id, event: "login_failed", ip: clientIp(request), meta: { reason: "2fa-verify" } });
    return errorResponse(401, "invalid_code");
  }
  await db.user.update({ where: { id: user.id }, data: { twoFactorEnabled: true } });
  await audit({ userId: user.id, event: "2fa_enabled", ip: clientIp(request), meta: { stage: "verified" } });
  return Response.json({ ok: true, twoFactorEnabled: true }, { headers: { "cache-control": "no-store" } });
}
