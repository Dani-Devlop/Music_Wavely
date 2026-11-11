/**
 * S18 / S38 / S66 — registration: strict validation, disposable-email check,
 * password policy, separate rate limits (IP + email), terms timestamp,
 * Argon2id hashing, hashed one-time verification token, uniform response.
 */
import { db } from "@/lib/db";
import { errorResponse, clientIp, parseStrict } from "@/lib/wavely/server/api-guard";
import { RegisterSchema } from "@/lib/wavely/server/validation";
import {
  hashPassword,
  checkPasswordPolicy,
  isDisposableEmail,
  UNIFORM_REGISTER_RESPONSE,
  registrationKeys,
} from "@/lib/wavely/server/password";
import { newToken, hashToken } from "@/lib/wavely/server/tokens";
import { audit } from "@/lib/wavely/server/audit";
import { rateLimit } from "@/lib/wavely/server/rate-limit";

const VERIFY_TOKEN_TTL_MIN = 30; // one-time tokens live 30min

export async function POST(request: Request) {
  // T-S38-7: separate limits per IP and per email
  const ip = clientIp(request);
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "invalid_json");
  }
  const parsed = parseStrict(RegisterSchema, body);
  if (!parsed.ok) return errorResponse(parsed.status, parsed.code); // uniform — no field detail

  const { email, username, password, termsAccepted } = parsed.data;

  const ipRate = rateLimit(`register:ip:${ip}`, 5, 3600);
  if (!ipRate.allowed) {
    const res = errorResponse(429, "rate_limited");
    res.headers.set("retry-after", String(ipRate.retryAfter));
    return res;
  }
  const { emailKey } = registrationKeys(ip, email);
  const emailRate = rateLimit(emailKey, 3, 3600);
  if (!emailRate.allowed) {
    const res = errorResponse(429, "rate_limited");
    res.headers.set("retry-after", String(emailRate.retryAfter));
    return res;
  }

  // T-S66-6: disposable domains rejected
  if (isDisposableEmail(email)) {
    return errorResponse(400, "registration_failed");
  }
  // T-S66-3: policy check (offline breached-list included)
  const policy = await checkPasswordPolicy(password);
  if (!policy.ok) {
    return errorResponse(400, "registration_failed");
  }
  if (!termsAccepted) {
    return errorResponse(400, "registration_failed");
  }

  const existing = await db.user.findFirst({ where: { OR: [{ email }, { username }] } });
  if (existing) {
    // T-S47-3: uniform response — never disclose which part exists
    return Response.json({ ok: true, message: UNIFORM_REGISTER_RESPONSE }, { status: 202, headers: { "cache-control": "no-store" } });
  }

  const passwordHash = await hashPassword(password);
  const user = await db.user.create({
    data: {
      email,
      username,
      passwordHash,
      name: username,
      displayName: username,
      termsAcceptedAt: new Date(), // T-S66-7: timestamped acceptance
    },
  });

  // Hashed one-time verification token (T-S66-15 semantics; TTL 30min)
  const verificationToken = newToken();
  await db.emailVerification.create({
    data: {
      userId: user.id,
      tokenHash: hashToken(verificationToken),
      expiresAt: new Date(Date.now() + VERIFY_TOKEN_TTL_MIN * 60 * 1000),
    },
  });
  // Delivery is the mail worker's job; the token never enters any response.

  await audit({ userId: user.id, event: "new_device", ip, userAgent: request.headers.get("user-agent"), meta: { flow: "registration" } });

  // T-S66-1 / T-S38-16: uniform, non-committal response
  return Response.json({ ok: true, message: UNIFORM_REGISTER_RESPONSE }, { status: 202, headers: { "cache-control": "no-store" } });
}

/** GET: confirm email via one-time token (?t=...) — T-S18-3. */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const token = url.searchParams.get("t");
  if (!token) return errorResponse(400, "invalid_token");
  const row = await db.emailVerification.findUnique({ where: { tokenHash: hashToken(token) } });
  if (!row || row.usedAt || row.expiresAt.getTime() < Date.now()) {
    return errorResponse(400, "invalid_token");
  }
  await db.$transaction([
    db.user.update({ where: { id: row.userId }, data: { emailVerified: true } }),
    db.emailVerification.update({ where: { id: row.id }, data: { usedAt: new Date() } }),
  ]);
  await audit({ userId: row.userId, event: "login", meta: { method: "email-verification" } });
  return Response.json({ ok: true, verified: true }, { headers: { "cache-control": "no-store" } });
}
