/**
 * S21 / S29-3 / S53 — multi-layer cache with per-user keys, TTL, atomic
 * invalidation, stampede protection and separated namespaces.
 *
 * Namespaces (T-S21-1): profile | settings | library | search | lyrics | offline
 * - profile/settings/library/search are server-side caches (L2).
 * - "offline" is the offline-audio cache namespace — kept separate from
 *   metadata/UI caches (S21-5).
 * - L1 = short-TTL in-process memo; L2 = this store (DB-backed in the
 *   prototype, Redis in production); L3 = CDN (headers only — no private
 *   data is publicly cacheable, T-S53-3).
 * Stampede protection: concurrent getters for the same key share one promise.
 */
import { db } from "@/lib/db";
import { leaksSecret } from "./env";

export const CACHE_NAMESPACES = ["profile", "settings", "library", "search", "lyrics", "offline"] as const;
export type CacheNamespace = (typeof CACHE_NAMESPACES)[number];

export interface CacheOptions {
  /** seconds */
  ttl: number;
}

const L1_TTL_MS = 30_000; // S29-3: L1 lives seconds–1 minute
const MAX_VALUE_BYTES = 4 * 1024; // S41-6 symmetry: keep cached payloads small

interface L1Entry {
  value: string;
  loadedAt: number;
}

const l1 = new Map<string, L1Entry>();
const inflight = new Map<string, Promise<string | null>>();

/** Public/private flag for CDN headers (T-S53-3): profile/settings/library/search/lyrics are private. */
export const PRIVATE_NAMESPACES: readonly CacheNamespace[] = ["profile", "settings", "library", "search", "lyrics"];

export function isPrivateNamespace(ns: CacheNamespace): boolean {
  return PRIVATE_NAMESPACES.includes(ns);
}

/** Per-user key builder (T-S53-2 / T-S72-4): "ns:userId:entity". */
export function cacheKey(ns: CacheNamespace, userId: string | null, entity: string): string {
  return `${ns}:${userId ?? "global"}:${entity}`;
}

async function readL2(key: string): Promise<string | null> {
  const row = await db.cacheEntry.findUnique({ where: { key } });
  if (!row) return null;
  if (row.expiresAt.getTime() <= Date.now()) {
    await db.cacheEntry.delete({ where: { key } }).catch(() => undefined);
    return null;
  }
  return row.value;
}

async function writeL2(key: string, ns: CacheNamespace, userId: string | null, value: string, ttl: number) {
  if (Buffer.byteLength(value, "utf8") > MAX_VALUE_BYTES) return; // never store big/sensitive blobs
  if (leaksSecret(value)) return; // T-S53-1: token-shaped secrets never enter the cache
  const expiresAt = new Date(Date.now() + ttl * 1000);
  await db.cacheEntry.upsert({
    where: { key },
    create: { key, namespace: ns, userId, value, expiresAt },
    update: { value, expiresAt, namespace: ns, userId },
  });
}

/**
 * Get-or-load with stampede protection (T-S29-5): N concurrent callers for a
 * cold key trigger exactly one loader.
 */
export async function cacheGet<T>(
  ns: CacheNamespace,
  userId: string | null,
  entity: string,
  loader: () => Promise<T>,
  opts: CacheOptions,
): Promise<T | null> {
  const key = cacheKey(ns, userId, entity);
  const now = Date.now();
  const memo = l1.get(key);
  if (memo && now - memo.loadedAt < L1_TTL_MS) {
    return JSON.parse(memo.value) as T;
  }
  const cached = await readL2(key);
  if (cached !== null) {
    l1.set(key, { value: cached, loadedAt: now });
    return JSON.parse(cached) as T;
  }
  // stampede guard
  const existing = inflight.get(key);
  if (existing) return JSON.parse((await existing) ?? "null") as T | null;
  const p = (async () => {
    const fresh = await loader();
    if (fresh !== null && fresh !== undefined) {
      const value = JSON.stringify(fresh);
      l1.set(key, { value, loadedAt: Date.now() });
      await writeL2(key, ns, userId, value, opts.ttl);
    }
    return fresh === undefined ? null : (JSON.stringify(fresh) as string);
  })().finally(() => inflight.delete(key));
  inflight.set(key, p);
  const result = await p;
  return result === null ? null : (JSON.parse(result) as T);
}

/** S53-4: atomic invalidate — L1 + L2 removed in one logical step. */
export async function cacheInvalidate(ns: CacheNamespace, userId: string | null, entity: string): Promise<void> {
  const key = cacheKey(ns, userId, entity);
  l1.delete(key);
  await db.cacheEntry.deleteMany({ where: { key } });
}

/** Invalidate a whole namespace for one user (profile/avatar/settings/library changes — T-S21-4). */
export async function cacheInvalidateUser(ns: CacheNamespace, userId: string): Promise<void> {
  for (const [key] of l1) if (key.startsWith(`${ns}:${userId}:`) || key.startsWith(`${ns}:null:`)) l1.delete(key);
  await db.cacheEntry.deleteMany({ where: { namespace: ns, OR: [{ userId }, { userId: null }] } });
}

/** Cache size stats for Settings (S72-3: حجم کش). */
export async function cacheStats(userId: string): Promise<{ entries: number; bytes: number; byNamespace: Record<string, number> }> {
  const rows = await db.cacheEntry.findMany({ where: { OR: [{ userId }, { userId: null }] } });
  const byNamespace: Record<string, number> = {};
  let bytes = 0;
  for (const r of rows) {
    const b = Buffer.byteLength(r.value, "utf8");
    bytes += b;
    byNamespace[r.namespace] = (byNamespace[r.namespace] ?? 0) + b;
  }
  return { entries: rows.length, bytes, byNamespace };
}

/** Secure clearing — requires explicit confirmation (T-S72-6). */
export async function cacheClearAll(userId: string, confirm: boolean): Promise<number> {
  if (!confirm) throw new Error("cache clearing requires explicit confirmation");
  const rows = await db.cacheEntry.findMany({ where: { OR: [{ userId }, { userId: null }] }, select: { key: true } });
  for (const r of rows) l1.delete(r.key);
  const res = await db.cacheEntry.deleteMany({ where: { OR: [{ userId }, { userId: null }] } });
  return res.count;
}

export async function cacheClearNamespace(userId: string, ns: CacheNamespace, confirm: boolean): Promise<number> {
  if (!confirm) throw new Error("cache clearing requires explicit confirmation");
  for (const [key] of l1) if (key.startsWith(`${ns}:${userId}:`) || key.startsWith(`${ns}:null:`)) l1.delete(key);
  return db.cacheEntry.deleteMany({ where: { namespace: ns, OR: [{ userId }, { userId: null }] } }).then((r) => r.count);
}
