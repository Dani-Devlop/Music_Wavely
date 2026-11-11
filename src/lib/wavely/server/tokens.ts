/**
 * Opaque token helpers — S18-9, S38-11, S38-15, S40-1.
 * Tokens are ≥256-bit random, only their SHA-256 hash is persisted.
 */
import { createHash, randomBytes } from "crypto";

/** 32 random bytes → 43-char url-safe token (≥128-bit; we use 256-bit). */
export function newToken(bytes = 32): string {
  return randomBytes(bytes).toString("base64url");
}

/** SHA-256 hex hash of a token — this (never the token) is what we store. */
export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/** 6-digit one-time room PIN (S04-4). */
export function newPin6(): string {
  return String(randomBytes(4).readUInt32BE(0) % 1000000).padStart(6, "0");
}
