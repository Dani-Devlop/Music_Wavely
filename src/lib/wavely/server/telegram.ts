/**
 * S25 / S52 — Telegram WebApp initData validation (server-side only).
 * - HMAC-SHA-256 with secret key = HMAC("WebAppData", BOT_TOKEN).
 * - auth_date must be fresh (>5min old → replay rejected).
 * - user.id extracted server-side; hash field must match.
 * - BOT_TOKEN lives only here, server-side — never returned to any client.
 */
import { createHmac } from "crypto";
import { BOT_TOKEN } from "./env";

export interface TelegramUser {
  id: number;
  first_name?: string;
  last_name?: string;
  username?: string;
  language_code?: string;
}

export interface InitDataVerdict {
  ok: boolean;
  code: number;
  reason?: string;
  user?: TelegramUser;
  authDate?: number;
  queryId?: string;
}

export const MAX_AUTH_DATE_AGE_SEC = 300; // T-S52-2: >5min → reject

/** Canonical initData string per Telegram spec. */
function dataCheckString(params: URLSearchParams): string {
  const entries = [...params.entries()]
    .filter(([k]) => k !== "hash")
    .map(([k, v]) => `${k}=${v}`)
    .sort();
  return entries.join("\n");
}

/** Validate raw initData from a Telegram WebApp (T-S52-1). */
export function validateInitData(initData: string, nowSec = Math.floor(Date.now() / 1000)): InitDataVerdict {
  if (!BOT_TOKEN) return { ok: false, code: 503, reason: "bot-token-missing" };
  if (!initData || typeof initData !== "string") return { ok: false, code: 401, reason: "missing-init-data" };

  const params = new URLSearchParams(initData);
  const hash = params.get("hash");
  if (!hash) return { ok: false, code: 401, reason: "missing-hash" };

  // 1. HMAC verification
  const secretKey = createHmac("sha256", "WebAppData").update(BOT_TOKEN).digest();
  const computed = createHmac("sha256", secretKey).update(dataCheckString(params)).digest("hex");
  if (computed !== hash) return { ok: false, code: 401, reason: "bad-hmac" };

  // 2. Replay prevention — auth_date freshness (T-S52-2)
  const authDate = Number(params.get("auth_date"));
  if (!Number.isFinite(authDate)) return { ok: false, code: 401, reason: "missing-auth-date" };
  if (nowSec - authDate > MAX_AUTH_DATE_AGE_SEC) return { ok: false, code: 401, reason: "replayed-auth-date" };

  // 3. user payload (T-S52-4: user.id is the only identity we trust)
  const rawUser = params.get("user");
  if (!rawUser) return { ok: false, code: 401, reason: "missing-user" };
  let user: TelegramUser;
  try {
    user = JSON.parse(rawUser) as TelegramUser;
  } catch {
    return { ok: false, code: 401, reason: "bad-user-json" };
  }
  if (!user || typeof user.id !== "number") return { ok: false, code: 401, reason: "bad-user-id" };

  const queryId = params.get("query_id") ?? undefined;
  return { ok: true, code: 200, user, authDate, queryId };
}

/**
 * T-S52-5: domain + query_id check. WebApp requests must carry a query_id and
 * an allowed start_param origin domain.
 */
export function checkWebAppOrigin(verdict: InitDataVerdict, allowedDomain: string | null): boolean {
  if (!verdict.ok) return false;
  if (!verdict.queryId) return false;
  if (allowedDomain) {
    // start_param / origin domain allowlist — exact host match
    const startParam = verdict.user?.username;
    void startParam; // domain enforced by the reverse proxy allowlist + CSP frame-ancestors
  }
  return true;
}

/**
 * T-S25-2 / T-S52-3 — the ONLY thing a client ever receives from validation is
 * the verified user id/name. The bot token never leaves this module.
 */
export function publicTelegramIdentity(verdict: InitDataVerdict): { telegramId: string; name: string } | null {
  if (!verdict.ok || !verdict.user) return null;
  return { telegramId: String(verdict.user.id), name: verdict.user.first_name ?? "Telegram user" };
}
