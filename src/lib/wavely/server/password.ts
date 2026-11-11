/**
 * S18 / S38 / S66 — password hashing (Argon2id / bcrypt cost≥12), policy with
 * HIBP k-anonymity (offline breached-list fallback when network is blocked),
 * constant-time verification, disposable-email rejection, uniform messages.
 */
import { createHash, randomBytes, timingSafeEqual } from "crypto";
import bcrypt from "bcryptjs";
import { PASSWORD_PEPPER } from "./env";

export const BCRYPT_COST = 12; // MUST: cost ≥ 12
export const MIN_PASSWORD_LENGTH = 12;

export type HashAlgorithm = "bcrypt";

/** S38-1: bcrypt cost 12 (Argon2id-equivalent acceptance per master prompt "Argon2id یا bcrypt cost مناسب") with pepper. */
export async function hashPassword(password: string, algorithm: HashAlgorithm = "bcrypt"): Promise<string> {
  void algorithm;
  return bcrypt.hash(withPepper(password), BCRYPT_COST);
}

/** S38-3: constant-time verify (bcryptjs compare is timing-safe). */
export async function verifyPassword(password: string, hash: string): Promise<boolean> {
  try {
    return bcrypt.compare(withPepper(password), hash);
  } catch {
    return false;
  }
}

/** S38-2: pepper from secret manager/env — mixed before hashing, never stored. */
function withPepper(password: string): string {
  return PASSWORD_PEPPER ? `${PASSWORD_PEPPER}:${password}` : password;
}

// ─── Policy ──────────────────────────────────────────────────────────────────

export interface PasswordPolicyResult {
  ok: boolean;
  problems: string[];
}

/** S38-4: ≥12 chars, mixed classes, not in breached list (HIBP k-anonymity or offline fallback). */
export async function checkPasswordPolicy(password: string, opts: { network?: boolean } = {}): Promise<PasswordPolicyResult> {
  const problems: string[] = [];
  if (password.length < MIN_PASSWORD_LENGTH) problems.push("min-length-12");
  if (!/[a-z]/.test(password)) problems.push("needs-lowercase");
  if (!/[A-Z]/.test(password)) problems.push("needs-uppercase");
  if (!/[0-9]/.test(password)) problems.push("needs-digit");
  if (!/[^A-Za-z0-9]/.test(password)) problems.push("needs-symbol");
  if (await isBreached(password, opts)) problems.push("breached");
  return { ok: problems.length === 0, problems };
}

const OFFLINE_BREACHED_TOP = new Set([
  "password", "123456", "123456789", "12345678", "qwerty", "abc123", "password1",
  "iloveyou", "admin", "welcome", "monkey", "dragon", "letmein", "football",
  "password123", "qwerty123", "1q2w3e4r", "zaq12wsx", "passw0rd!", "p@ssw0rd",
]);

/** HIBP k-anonymity — SHA-1 prefix over the network; offline denylist fallback. */
export async function isBreached(password: string, opts: { network?: boolean } = {}): Promise<boolean> {
  if (OFFLINE_BREACHED_TOP.has(password.toLowerCase())) return true;
  const allowNetwork = opts.network ?? (process.env.HIBP_NETWORK === "on");
  if (!allowNetwork) return false; // offline sandbox: denylist decision only
  const sha1 = createHash("sha1").update(password).digest("hex").toUpperCase();
  const prefix = sha1.slice(0, 5);
  const suffix = sha1.slice(5);
  try {
    const res = await fetch(`https://api.pwnedpasswords.com/range/${prefix}`, { signal: AbortSignal.timeout(3000) });
    if (!res.ok) return false;
    const body = await res.text();
    return body.split("\n").some((line) => line.split(":")[0]?.trim() === suffix);
  } catch {
    return false; // network unavailable → denylist verdict only
  }
}

// ─── Uniform messages (S47 / S38-5 / S66-8) ──────────────────────────────────

export const UNIFORM_LOGIN_FAILURE = "Unable to sign in with those credentials";
export const UNIFORM_RESET_RESPONSE = "If that email exists, a reset link has been sent";
export const UNIFORM_REGISTER_RESPONSE = "Check your inbox to finish creating your account";

// ─── Disposable email (S38-14 / S66-6) ───────────────────────────────────────

const DISPOSABLE_DOMAINS = new Set([
  "mailinator.com", "guerrillamail.com", "10minutemail.com", "tempmail.com",
  "throwawaymail.com", "yopmail.com", "trashmail.com", "sharklasers.com",
  "getnada.com", "dispostable.com",
]);

export function isDisposableEmail(email: string): boolean {
  const domain = email.toLowerCase().split("@")[1] ?? "";
  return DISPOSABLE_DOMAINS.has(domain);
}

// ─── Timing-safe token comparison for reset/verification flows ───────────────

export function timingSafeCompareHex(aHex: string, bHex: string): boolean {
  const a = Buffer.from(aHex, "utf8");
  const b = Buffer.from(bHex, "utf8");
  if (a.length !== b.length) {
    timingSafeEqual(a, a);
    return false;
  }
  return timingSafeEqual(a, b);
}

/** Registration rate key helper — per IP and per email (S38-7). */
export function registrationKeys(ip: string, email: string): { ipKey: string; emailKey: string } {
  return { ipKey: `register:ip:${ip}`, emailKey: `register:email:${createHash("sha256").update(email).digest("hex")}` };
}

/** New-device fingerprint for alerts (S38-10). */
export function deviceFingerprint(userAgent: string | null, ip: string | null): string {
  return createHash("sha256").update(`${userAgent ?? ""}|${ip ?? ""}`).digest("hex").slice(0, 16);
}

/** Random verification code (email confirm, 2FA email-OTP fallback). */
export function newEmailOtp(): string {
  return String(100000 + (randomBytes(4).readUInt32BE(0) % 900000));
}
