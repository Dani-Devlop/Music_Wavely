/**
 * S54 — audit log: append-only, immutable, redacted.
 * Events: login, logout, failed_attempts, password_change, 2FA_change,
 * email_change, session_revocation, account_deletion, role_change,
 * ai_out_of_scope, new_device, data_export.
 * No secrets/tokens are ever written (T-S54-3). IPs are truncated for privacy.
 */
import { db } from "@/lib/db";
import { leaksSecret } from "./env";

export const AUDIT_EVENTS = [
  "login",
  "logout",
  "login_failed",
  "password_change",
  "2fa_enabled",
  "2fa_disabled",
  "email_change",
  "session_revoked",
  "sessions_revoked_all",
  "account_deleted",
  "role_change",
  "ai_out_of_scope",
  "new_device",
  "data_export",
  "cache_cleared",
  "avatar_change",
  "profile_update",
] as const;
export type AuditEvent = (typeof AUDIT_EVENTS)[number];

/** Privacy: /24 (IPv4) or /48 (IPv6) truncation (T-S54-4). */
export function truncateIp(ip: string | null | undefined): string | null {
  if (!ip) return null;
  if (ip.includes(":")) {
    const groups = ip.split(":").slice(0, 3).join(":");
    return `${groups}::`;
  }
  const octets = ip.split(".");
  if (octets.length !== 4) return null;
  return `${octets[0]}.${octets[1]}.${octets[2]}.0/24`;
}

export interface AuditInput {
  userId?: string | null;
  event: AuditEvent;
  ip?: string | null;
  userAgent?: string | null;
  meta?: Record<string, string | number | boolean | null>;
}

/** Append-only write. Throws when a secret pattern would be persisted. */
export async function audit(input: AuditInput): Promise<void> {
  const serializedMeta = input.meta ? JSON.stringify(redactMeta(input.meta)) : null;
  if (serializedMeta && leaksSecret(serializedMeta)) {
    throw new Error("audit: refusing to persist secret-shaped meta");
  }
  await db.auditLog.create({
    data: {
      userId: input.userId ?? null,
      event: input.event,
      ip: truncateIp(input.ip),
      userAgent: input.userAgent?.slice(0, 180) ?? null,
    },
  });
  void serializedMeta;
}

function redactMeta(meta: Record<string, string | number | boolean | null>): Record<string, string | number | boolean | null> {
  const out: Record<string, string | number | boolean | null> = {};
  for (const [k, v] of Object.entries(meta)) {
    out[k] = typeof v === "string" ? redactString(v) : v;
  }
  return out;
}

const SENSITIVE_KEYS = /(token|secret|password|cookie|authorization|api[_-]?key)/i;

function redactString(v: string): string {
  if (SENSITIVE_KEYS.test(v)) return "[REDACTED]";
  if (leaksSecret(v)) return "[REDACTED]";
  return v.slice(0, 120);
}

/** T-S54-2: append-only — no update/delete API exists by design. */
export async function listAudit(userId: string, limit = 50) {
  return db.auditLog.findMany({
    where: { userId },
    orderBy: { createdAt: "desc" },
    take: limit,
    select: { id: true, event: true, ip: true, userAgent: true, createdAt: true },
  });
}

/** T-S54-5: pattern alerting — failed-login burst on the same truncated IP. */
export async function suspiciousFailures(windowMinutes = 10, threshold = 5): Promise<{ ip: string; count: number }[]> {
  const since = new Date(Date.now() - windowMinutes * 60 * 1000);
  const rows = await db.auditLog.findMany({ where: { event: "login_failed", createdAt: { gte: since } } });
  const counts = new Map<string, number>();
  for (const r of rows) {
    const key = r.ip ?? "unknown";
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .filter(([, c]) => c >= threshold)
    .map(([ip, count]) => ({ ip, count }));
}
