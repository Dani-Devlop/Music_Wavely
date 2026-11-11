/**
 * S44 / S48 — input validation, injection defence helpers.
 * - Zod strict schemas (unknown fields rejected)
 * - magic-byte sniffing (never trust extension)
 * - path-traversal guard, SSRF allowlist, command-injection rejection,
 *   deserialization hardening
 */
import { z } from "zod";

// ── Strict schemas ───────────────────────────────────────────────────────────

export const ProfileUpdateSchema = z
  .object({
    name: z.string().min(1).max(64).regex(/^[\p{L}\p{N} '_-]+$/u),
    displayName: z.string().min(1).max(64).regex(/^[\p{L}\p{N} '_-]+$/u).optional(),
    email: z.string().email().max(254),
    language: z.enum(["en", "fa", "ru", "ar", "tr"]).optional(),
    theme: z.enum(["system", "light", "dark"]).optional(),
    avatar: z.string().max(512).optional(),
  })
  .strict(); // T-S48-4

export const RegisterSchema = z
  .object({
    email: z.string().email().max(254),
    username: z.string().min(3).max(32).regex(/^[a-zA-Z0-9_]+$/),
    password: z.string().min(12).max(128),
    termsAccepted: z.literal(true),
  })
  .strict();

export const LoginSchema = z
  .object({
    email: z.string().email().max(254),
    password: z.string().min(1).max(128),
    remember: z.boolean().optional(),
    otp: z.string().max(8).optional(),
  })
  .strict();

export const AgentChatSchema = z
  .object({
    message: z.string().min(1).max(2000),
  })
  .strict();

export const CacheClearSchema = z
  .object({
    scope: z.enum(["all", "profile", "settings", "library", "search", "lyrics", "offline"]),
    confirm: z.literal(true),
  })
  .strict();

export const PlayerControlSchema = z
  .object({
    action: z.enum(["play", "pause", "seek", "next", "previous", "shuffle", "loop"]),
    positionSec: z.number().min(0).max(3600).optional(),
  })
  .strict();

export const QueueAddSchema = z
  .object({
    trackId: z.string().min(1).max(64),
  })
  .strict();

// ── Magic bytes (T-S48-5 / T-S49-1) ──────────────────────────────────────────

export type ImageFormat = "jpeg" | "png" | "webp";
export type AudioFormat = "mp3" | "aac" | "ogg";

export function sniffImage(bytes: Uint8Array): ImageFormat | null {
  if (bytes.length < 12) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "jpeg";
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "png";
  // RIFF....WEBP
  if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) return "webp";
  return null;
}

export function sniffAudio(bytes: Uint8Array): AudioFormat | null {
  if (bytes.length < 12) return null;
  if (bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33) return "mp3"; // ID3
  if (bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0) return "mp3"; // MPEG frame sync
  if (bytes[0] === 0x4f && bytes[1] === 0x67 && bytes[2] === 0x67 && bytes[3] === 0x53) return "ogg";
  // ADTS AAC: 0xFF Fx
  if (bytes[0] === 0xff && (bytes[1] & 0xf6) === 0xf0) return "aac";
  return null;
}

// ── Injection helpers ────────────────────────────────────────────────────────

/** T-S44-4: reject shell metacharacters in any string that could reach exec. */
export function containsCommandMeta(value: string): boolean {
  return /[;&|`$><\n\r\\]/.test(value);
}

/** T-S44-6: path traversal guard — resolved path must stay in the base dir. */
export function isPathSafe(baseDir: string, relative: string): boolean {
  const path = require("path") as typeof import("path");
  const resolved = path.resolve(baseDir, relative);
  return resolved.startsWith(path.resolve(baseDir) + path.sep);
}

/** T-S44-5: SSRF allowlist — only these upstream hosts may be fetched. */
const SSRF_ALLOWLIST = new Set([
  "api.jamendo.com",
  "freemusicarchive.org",
  "archive.org",
  "lrclib.net",
  "api.pwnedpasswords.com",
]);

export function isAllowedUpstream(url: string): boolean {
  try {
    const u = new URL(url);
    if (u.protocol !== "https:") return false;
    return SSRF_ALLOWLIST.has(u.hostname);
  } catch {
    return false;
  }
}

/** T-S44-2: reject NoSQL/operator injection shapes in user JSON. */
export function containsNoSqlOperator(value: unknown): boolean {
  if (typeof value === "string") return /[$]\s*(gt|lt|ne|eq|where|regex|or|and)/i.test(value);
  if (Array.isArray(value)) return value.some(containsNoSqlOperator);
  if (value && typeof value === "object") return Object.values(value).some(containsNoSqlOperator);
  return false;
}

/** T-S44-7: JSON deserialization with size + prototype-pollution guard. */
export function safeJsonParse<T>(raw: string, maxBytes = 64 * 1024): T | null {
  if (Buffer.byteLength(raw, "utf8") > maxBytes) return null;
  if (/__proto__|constructor|prototype/.test(raw)) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

/** T-S44-3: search-input sanitization — strip control chars, cap length, escape regex. */
export function sanitizeSearchInput(q: string): string {
  const stripped = q.replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, 128);
  return stripped.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
