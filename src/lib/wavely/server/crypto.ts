/**
 * S50 — field-level encryption helpers (KMS/env-backed key, rotatable) and
 * log redaction for the prototype's secret store.
 */
import { createCipheriv, createDecipheriv, createHash, randomBytes } from "crypto";

const ALGO = "aes-256-gcm";

function keyFromSecret(): Buffer {
  const secret = process.env.AUTH_SECRET ?? "";
  if (!secret) throw new Error("AUTH_SECRET missing — cannot encrypt fields");
  return createHash("sha256").update(secret).digest();
}

/** AES-256-GCM encrypt a small secret field → v1:<iv>:<tag>:<ct> (b64url). */
export function encryptSecret(plain: string): string {
  const key = keyFromSecret();
  const iv = randomBytes(12);
  const cipher = createCipheriv(ALGO, key, iv);
  const ct = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return ["v1", iv.toString("base64url"), tag.toString("base64url"), ct.toString("base64url")].join(":");
}

export function decryptSecret(payload: string): string | null {
  try {
    const [version, ivB, tagB, ctB] = payload.split(":");
    if (version !== "v1") return null;
    const key = keyFromSecret();
    const decipher = createDecipheriv(ALGO, key, Buffer.from(ivB, "base64url"));
    decipher.setAuthTag(Buffer.from(tagB, "base64url"));
    const pt = Buffer.concat([decipher.update(Buffer.from(ctB, "base64url")), decipher.final()]);
    return pt.toString("utf8");
  } catch {
    return null;
  }
}

/** T-S50-7: rotation — re-encrypt under a fresh derived key version. */
export function reencrypt(payload: string, newSecret: string, decryptFn = decryptSecret): string | null {
  const plain = decryptFn(payload);
  if (plain === null) return null;
  const key = createHash("sha256").update(newSecret).digest();
  const iv = randomBytes(12);
  const cipher = createCipheriv(ALGO, key, iv);
  const ct = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return ["v1", iv.toString("base64url"), tag.toString("base64url"), ct.toString("base64url")].join(":");
}

/** T-S50-8: log lines never contain secret-shaped material. */
export function redactForLog(text: string): string {
  return text
    .replace(/\b\d{8,12}:AA[\w-]{20,}\b/g, "[REDACTED]")
    .replace(/\bapp\d+:[\w]{20,}\b/g, "[REDACTED]")
    .replace(/(authorization|password|token|secret)["']?\s*[:=]\s*\S+/gi, "$1=[REDACTED]");
}
