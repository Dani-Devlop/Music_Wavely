/**
 * S39 / S67 — TOTP (RFC 6238) with base32 secrets, otpauth URIs, one-time
 * display of the QR secret, hashed one-time recovery codes and severe rate
 * limiting on verification attempts.
 */
import { createHmac, randomBytes, createHash } from "crypto";
import { newToken, hashToken } from "./tokens";

const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export function base32Encode(buf: Buffer): string {
  let bits = 0;
  let value = 0;
  let out = "";
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  return out;
}

export function base32Decode(input: string): Buffer {
  const clean = input.toUpperCase().replace(/=+$/, "").replace(/\s/g, "");
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const ch of clean) {
    const idx = BASE32_ALPHABET.indexOf(ch);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

export interface TotpSetup {
  secret: string; // base32 — shown exactly once (T-S39-3)
  otpauthUri: string;
}

/** Generate a new TOTP secret — returned in plaintext ONCE, stored encrypted. */
export function totpSetup(account: string, issuer = "Wavely"): TotpSetup {
  const secret = base32Encode(randomBytes(20));
  const otpauthUri = `otpauth://totp/${encodeURIComponent(issuer)}:${encodeURIComponent(account)}?secret=${secret}&issuer=${encodeURIComponent(issuer)}&algorithm=SHA1&digits=6&period=30`;
  return { secret, otpauthUri };
}

/** RFC 6238 HMAC-SHA1, 6 digits, 30s step, ±1 window. */
export function totpAt(secretBase32: string, timeSec: number): string {
  const key = base32Decode(secretBase32);
  const counter = Math.floor(timeSec / 30);
  const buf = Buffer.alloc(8);
  buf.writeUInt32BE(Math.floor(counter / 2 ** 32), 0);
  buf.writeUInt32BE(counter % 2 ** 32, 4);
  const digest = createHmac("sha1", key).update(buf).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const bin =
    ((digest[offset] & 0x7f) << 24) |
    (digest[offset + 1] << 16) |
    (digest[offset + 2] << 8) |
    digest[offset + 3];
  return String(bin % 1_000_000).padStart(6, "0");
}

export interface TotpVerdict {
  ok: boolean;
  reason?: "bad-code" | "reused";
}

export interface TotpVerifyOptions {
  usedCodes?: string[]; // recently accepted codes (anti-replay within window)
}

/** Verify with ±1 step tolerance and replay protection. */
export function totpVerify(secretBase32: string, code: string, nowSec = Math.floor(Date.now() / 1000), opts: TotpVerifyOptions = {}): TotpVerdict {
  const clean = code.replace(/\s/g, "");
  if (!/^\d{6}$/.test(clean)) return { ok: false, reason: "bad-code" };
  for (const drift of [-1, 0, 1]) {
    const expected = totpAt(secretBase32, nowSec + drift * 30);
    if (expected === clean) {
      if (opts.usedCodes?.includes(`${drift}:${clean}`)) return { ok: false, reason: "reused" };
      return { ok: true };
    }
  }
  return { ok: false, reason: "bad-code" };
}

/** S39-2: one-time recovery codes — returned in plaintext ONCE, stored hashed. */
export function newRecoveryCodes(count = 8): { codes: string[]; hashes: string[] } {
  const codes: string[] = [];
  const hashes: string[] = [];
  for (let i = 0; i < count; i++) {
    const code = `${newToken(6).slice(0, 5)}-${newToken(6).slice(0, 5)}`.toLowerCase();
    codes.push(code);
    hashes.push(hashToken(code));
  }
  return { codes, hashes };
}

export function hashCode(code: string): string {
  return createHash("sha256").update(code).digest("hex");
}
