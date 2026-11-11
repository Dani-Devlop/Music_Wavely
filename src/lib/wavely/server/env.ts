/**
 * S02 / R02 — token separation. Tokens live ONLY in env vars, never in code,
 * never in logs, never in API responses, never committed to git.
 * Values in the master prompt are treated as <REDACTED> and read from .env.
 */
import { timingSafeEqual } from "crypto";

function readEnv(name: string): string {
  const v = process.env[name];
  return typeof v === "string" ? v : "";
}

/** Telegram Bot API token (`123456:AA...`) — for Bot API calls only. NEVER in tgcloud login. */
export const BOT_TOKEN = readEnv("BOT_TOKEN");
/** tgcloud CLI access token (`app<id>:<secret>`) — for `npx tgcloud login` only. */
export const TGCLI_TOKEN = readEnv("TGCLI_TOKEN");
/** Signing pepper (S38-2) — secret-manager/env sourced. */
export const PASSWORD_PEPPER = readEnv("PASSWORD_PEPPER");
/** JWT/session signing secret (rotatable — S50-7). */
export const AUTH_SECRET = readEnv("AUTH_SECRET");
/** Owner/admin Telegram ID for /admin gating (public value from the master prompt). */
export const OWNER_ID = readEnv("OWNER_ID") || "2040835005";

/** Patterns that must never appear in code, logs, tests or responses. */
export const SECRET_PATTERNS: RegExp[] = [
  /\b\d{8,12}:AA[\w-]{30,}\b/, // Bot API token shape
  /\bapp\d+:[\w]{20,}\b/, // tgcloud CLI token shape
  /AA[\w-]{34}\b/, // raw bot-token suffix
];

/** True when a string leaks a token-shaped secret — used by logs/audit redaction + DAST. */
export function leaksSecret(text: string): boolean {
  return SECRET_PATTERNS.some((re) => re.test(text));
}

/** Constant-time equality for short secrets. */
export function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) {
    // compare against self to keep timing constant, then fail
    timingSafeEqual(ab, ab);
    return false;
  }
  return timingSafeEqual(ab, bb);
}

/** Fail fast when a required secret is missing in production flows. */
export function requireBotToken(): string {
  if (!BOT_TOKEN) throw new Error("BOT_TOKEN missing from environment");
  return BOT_TOKEN;
}
