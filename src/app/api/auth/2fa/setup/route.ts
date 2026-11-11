/**
 * S39-1..4 / S67 — 2FA setup: generate TOTP secret (shown once), encrypted
 * at rest, QR one-time display, hashed one-time recovery codes.
 * Enabling 2FA is a sensitive operation (audit logged).
 */
import { db } from "@/lib/db";
import { requireAuth, requireCsrf, errorResponse, clientIp } from "@/lib/wavely/server/api-guard";
import { totpSetup, newRecoveryCodes } from "@/lib/wavely/server/totp";
import { encryptSecret } from "@/lib/wavely/server/crypto";
import { audit } from "@/lib/wavely/server/audit";

export async function POST(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);

  const user = await db.user.findUnique({ where: { id: auth.auth.userId } });
  if (!user) return errorResponse(404, "not_found");
  if (user.twoFactorEnabled) return errorResponse(409, "2fa-already-enabled");

  const { secret, otpauthUri } = totpSetup(user.email);
  // T-S39-4: secret stored encrypted (AES-256-GCM with server key)
  const encrypted = encryptSecret(secret);
  await db.user.update({ where: { id: user.id }, data: { twoFactorSecret: encrypted } });

  const { codes, hashes } = newRecoveryCodes();
  await db.recoveryCode.deleteMany({ where: { userId: user.id, usedAt: null } });
  await db.recoveryCode.createMany({ data: hashes.map((h) => ({ userId: user.id, codeHash: h })) });

  await audit({ userId: user.id, event: "2fa_enabled", ip: clientIp(request), meta: { stage: "setup" } });

  // T-S39-3: secret + QR payload shown exactly ONCE — client must render/store now
  return Response.json(
    { ok: true, otpauthUri, secret, recoveryCodes: codes, qrOnce: true },
    { headers: { "cache-control": "no-store" } },
  );
}
