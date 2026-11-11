/**
 * S18 / S38 / S66 — login: uniform error message, timing-constant path,
 * separate rate limits (IP + account), progressive lockout after 5 failures,
 * new-device alert, remember-me token, session rotation (anti-fixation),
 * HttpOnly cookies + CSRF token, 2FA challenge branch (S03-5).
 */
import { db } from "@/lib/db";
import { errorResponse, clientIp, guardRate, parseStrict } from "@/lib/wavely/server/api-guard";
import { LoginSchema } from "@/lib/wavely/server/validation";
import {
  verifyPassword,
  UNIFORM_LOGIN_FAILURE,
  deviceFingerprint,
} from "@/lib/wavely/server/password";
import { newToken, hashToken } from "@/lib/wavely/server/tokens";
import { createSession, sessionCookieName } from "@/lib/wavely/server/sessions";
import { issueCsrf } from "@/lib/wavely/server/csrf";
import { audit } from "@/lib/wavely/server/audit";
import { rateLimit } from "@/lib/wavely/server/rate-limit";
import { totpVerify } from "@/lib/wavely/server/totp";

const LOCKOUT_THRESHOLD = 5;
const LOCKOUT_MINUTES = 15;

/** A real throwaway hash so the failed path costs the same CPU as the success path (lazy, once). */
let dummyHashPromise: Promise<string> | null = null;
function getDummyHash(): Promise<string> {
  if (!dummyHashPromise) {
    dummyHashPromise = (async () => {
      const { hashPassword } = await import("@/lib/wavely/server/password");
      return hashPassword("wavely-timing-equalizer:" + Math.random());
    })();
  }
  return dummyHashPromise;
}

export async function POST(request: Request) {
  const ip = clientIp(request);
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "invalid_json");
  }
  const parsed = parseStrict(LoginSchema, body);
  if (!parsed.ok) {
    // T-S66-8: same uniform message for malformed input as for bad credentials
    return errorResponse(401, "login_failed", UNIFORM_LOGIN_FAILURE);
  }
  const { email, password, remember, otp } = parsed.data;

  // T-S66-10: separate IP + account limits
  const ipRate = rateLimit(`login:ip:${ip}`, 10, 300);
  if (!ipRate.allowed) {
    const res = errorResponse(429, "rate_limited");
    res.headers.set("retry-after", String(ipRate.retryAfter));
    return res;
  }
  const acctHash = hashToken(email.toLowerCase());
  const acctRate = rateLimit(`login:acct:${acctHash}`, 5, 300);
  if (!acctRate.allowed) {
    const res = errorResponse(429, "rate_limited");
    res.headers.set("retry-after", String(acctRate.retryAfter));
    return res;
  }

  const user = await db.user.findUnique({ where: { email } });

  if (!user) {
    // T-S66-9: run the same verification work to keep timing constant
    await verifyPassword(password, await getDummyHash());
    await db.loginAttempt.create({ data: { email, ip, success: false } });
    await audit({ event: "login_failed", ip, meta: { reason: "no-user" } });
    return errorResponse(401, "login_failed", UNIFORM_LOGIN_FAILURE);
  }

  if (user.lockoutUntil && user.lockoutUntil.getTime() > Date.now()) {
    // T-S66-11: progressive lockout
    return errorResponse(429, "locked", UNIFORM_LOGIN_FAILURE);
  }

  const okHash = user.passwordHash ? await verifyPassword(password, user.passwordHash) : false;
  if (!okHash) {
    await db.loginAttempt.create({ data: { email, ip, success: false } });
    const failed = user.failedAttempts + 1;
    await db.user.update({
      where: { id: user.id },
      data: {
        failedAttempts: failed,
        ...(failed >= LOCKOUT_THRESHOLD ? { lockoutUntil: new Date(Date.now() + LOCKOUT_MINUTES * 60 * 1000) } : {}),
      },
    });
    await audit({ userId: user.id, event: "login_failed", ip, meta: { attempt: failed } });
    return errorResponse(401, "login_failed", UNIFORM_LOGIN_FAILURE);
  }

  // 2FA branch (T-S03-5): when enabled, no session until a valid TOTP/recovery code arrives
  if (user.twoFactorEnabled) {
    if (!otp) {
      return Response.json(
        { ok: false, error: { code: "two_factor_required" } },
        { status: 401, headers: { "cache-control": "no-store" } },
      );
    }
    const secretRow = await db.botConfig.findUnique({ where: { key: `2fa:${user.id}` } });
    const secret = secretRow?.value ?? "";
    const verdict = secret ? totpVerify(secret, otp) : { ok: false as const };
    if (!verdict.ok) {
      const rec = await db.recoveryCode.findFirst({
        where: { userId: user.id, codeHash: hashToken(otp), usedAt: null },
      });
      if (!rec) {
        await audit({ userId: user.id, event: "login_failed", ip, meta: { reason: "bad-2fa" } });
        return errorResponse(401, "login_failed", UNIFORM_LOGIN_FAILURE);
      }
      await db.recoveryCode.update({ where: { id: rec.id }, data: { usedAt: new Date() } }); // one-time
    }
  }

  // Success: reset failure counters, rotate session (anti-fixation — any
  // pre-auth anonymous session id dies because a brand-new token is minted)
  await db.user.update({ where: { id: user.id }, data: { failedAttempts: 0, lockoutUntil: null, lastLoginAt: new Date(), lastLoginIp: ip } });
  await db.loginAttempt.create({ data: { email, ip, success: true } });

  const ua = request.headers.get("user-agent");
  const fingerprint = deviceFingerprint(ua, ip);
  const knownDevice = await db.session.findFirst({
    where: { userId: user.id, deviceInfo: { contains: fingerprint } },
  });
  if (!knownDevice) {
    await db.deviceAlert.create({ data: { userId: user.id, device: ua?.slice(0, 60) ?? "unknown", ip } });
    await audit({ userId: user.id, event: "new_device", ip, userAgent: ua });
  }

  const secure = request.url.startsWith("https");
  const session = await createSession({
    userId: user.id,
    ip,
    deviceInfo: fingerprint,
    browser: ua?.slice(0, 60) ?? null,
    secure,
    remember,
  });

  // T-S18-9: remember-me token (revocable)
  if (remember) {
    const rt = newToken();
    await db.rememberToken.create({
      data: {
        userId: user.id,
        tokenHash: hashToken(rt),
        expiresAt: new Date(Date.now() + 30 * 24 * 3600 * 1000),
      },
    });
  }

  const csrf = await issueCsrf(session.sessionId);
  await audit({ userId: user.id, event: "login", ip, userAgent: ua, meta: { remember: remember ?? false } });

  const headers = new Headers({ "cache-control": "no-store" });
  const setCookie = (name: string, value: string, maxAge: number) => {
    const parts = [`${name}=${encodeURIComponent(value)}`, "Path=/", `Max-Age=${maxAge}`, "HttpOnly", "SameSite=Lax"];
    if (secure) parts.push("Secure");
    headers.append("set-cookie", parts.join("; "));
  };
  setCookie(sessionCookieName(secure), session.token, session.accessCookie.maxAge);
  setCookie("wavely_csrf", csrf.token, 3600);

  return new Response(
    JSON.stringify({ ok: true, csrfToken: csrf.token, user: { id: user.id, name: user.name } }),
    { status: 200, headers },
  );
}

void guardRate;
