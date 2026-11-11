/**
 * S21 / S72 — Cache management endpoint. Cache administration lives ONLY in
 * Settings (the UI mounts this exclusively under Settings → Cache); Explore
 * never calls it (T-S21-2 / T-S72-2). Clearing requires `confirm: true`
 * (T-S72-6) and is audited.
 */
import { requireAuth, requireCsrf, guardRate, errorResponse, clientIp, parseStrict } from "@/lib/wavely/server/api-guard";
import { cacheStats, cacheClearAll, cacheClearNamespace, cacheInvalidateUser, CACHE_NAMESPACES, type CacheNamespace } from "@/lib/wavely/server/cache";
import { CacheClearSchema } from "@/lib/wavely/server/validation";
import { audit } from "@/lib/wavely/server/audit";
import { db } from "@/lib/db";

export async function GET(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const rate = guardRate(request, "general", auth.auth.userId);
  if (!rate.ok) return errorResponse(rate.status, rate.code, rate.message);

  const stats = await cacheStats(auth.auth.userId);
  const userSetting = await db.userSetting.findUnique({ where: { userId: auth.auth.userId } });
  return Response.json(
    {
      ok: true,
      stats,
      options: {
        autoCache: userSetting?.autoCache ?? true,
        cacheLimitMb: userSetting?.cacheLimitMb ?? 400,
        namespaces: CACHE_NAMESPACES,
      },
    },
    { headers: { "cache-control": "no-store" } },
  );
}

export async function POST(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const rate = guardRate(request, "general", auth.auth.userId);
  if (!rate.ok) return errorResponse(rate.status, rate.code, rate.message);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "invalid_json");
  }
  const parsed = parseStrict(CacheClearSchema, body);
  if (!parsed.ok) return errorResponse(parsed.status, parsed.code);

  const { scope, confirm } = parsed.data;
  let cleared: number;
  if (scope === "all") {
    cleared = await cacheClearAll(auth.auth.userId, confirm);
    await cacheInvalidateUser("profile", auth.auth.userId);
    await cacheInvalidateUser("settings", auth.auth.userId);
  } else {
    cleared = await cacheClearNamespace(auth.auth.userId, scope as CacheNamespace, confirm);
  }
  await audit({ userId: auth.auth.userId, event: "cache_cleared", ip: clientIp(request), meta: { scope } });
  return Response.json({ ok: true, cleared }, { headers: { "cache-control": "no-store" } });
}

/** PUT: cache preferences (autoCache toggle, cache limit) — Settings only. */
export async function PUT(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);
  let body: { autoCache?: boolean; cacheLimitMb?: number };
  try {
    body = (await request.json()) as { autoCache?: boolean; cacheLimitMb?: number };
  } catch {
    return errorResponse(400, "invalid_json");
  }
  const autoCache = typeof body.autoCache === "boolean" ? body.autoCache : undefined;
  const cacheLimitMb = typeof body.cacheLimitMb === "number" && body.cacheLimitMb >= 50 && body.cacheLimitMb <= 4000 ? Math.round(body.cacheLimitMb) : undefined;
  if (autoCache === undefined && cacheLimitMb === undefined) return errorResponse(400, "invalid_input");
  await db.userSetting.upsert({
    where: { userId: auth.auth.userId },
    create: { userId: auth.auth.userId, autoCache: autoCache ?? true, cacheLimitMb: cacheLimitMb ?? 400 },
    update: { ...(autoCache !== undefined ? { autoCache } : {}), ...(cacheLimitMb !== undefined ? { cacheLimitMb } : {}) },
  });
  await cacheInvalidateUser("settings", auth.auth.userId);
  return Response.json({ ok: true }, { headers: { "cache-control": "no-store" } });
}
