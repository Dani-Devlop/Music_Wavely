/**
 * S19 / S71 — Profile: server-side truth of record.
 * GET  → fresh server record (cache "profile" namespace, invalidated on write).
 * PUT  → atomic UPDATE + SELECT-after-UPDATE + optimistic locking
 *        (`x-base-updated-at`) + immediate cache invalidation + audit.
 * The response is `cache-control: no-store` — the client must never cache a
 * profile (T-S19-1 / T-S71-1).
 */
import { db } from "@/lib/db";
import { requireAuth, requireCsrf, guardRate, errorResponse, clientIp, parseStrict } from "@/lib/wavely/server/api-guard";
import { ProfileUpdateSchema } from "@/lib/wavely/server/validation";
import { cacheGet, cacheInvalidateUser } from "@/lib/wavely/server/cache";
import { audit } from "@/lib/wavely/server/audit";

const PROFILE_TTL_SEC = 300;

export async function GET(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);

  const rate = guardRate(request, "general", auth.auth.userId);
  if (!rate.ok) {
    const res = errorResponse(rate.status, rate.code, rate.message);
    res.headers.set("retry-after", rate.message ?? "60");
    return res;
  }

  // server is the single source of truth; per-user cache with short TTL
  const profile = await cacheGet(
    "profile",
    auth.auth.userId,
    "me",
    async () => {
      const u = await db.user.findUnique({
        where: { id: auth!.auth!.userId },
        select: {
          id: true,
          name: true,
          displayName: true,
          email: true,
          avatar: true,
          language: true,
          theme: true,
          role: true,
          emailVerified: true,
          twoFactorEnabled: true,
          lastLoginAt: true,
          updatedAt: true,
        },
      });
      return u;
    },
    { ttl: PROFILE_TTL_SEC },
  );
  if (!profile) return errorResponse(404, "profile_missing");

  return Response.json(
    { ok: true, profile },
    {
      headers: {
        "cache-control": "no-store", // no client caching — T-S19-1
        "cdn-cache-control": "private, no-store", // T-S53-3: never publicly cached
      },
    },
  );
}

export async function PUT(request: Request) {
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
  const parsed = parseStrict(ProfileUpdateSchema, body);
  if (!parsed.ok) return errorResponse(parsed.status, parsed.code);

  const data = parsed.data;
  // Optimistic locking (T-S71-3): client sends the updatedAt its edit was based on.
  const baseUpdatedAt = request.headers.get("x-base-updated-at");

  try {
    const updated = await db.$transaction(async (tx) => {
      const current = await tx.user.findUnique({ where: { id: auth!.auth!.userId }, select: { updatedAt: true } });
      if (!current) throw Object.assign(new Error("missing"), { code: 404 });
      if (baseUpdatedAt && current.updatedAt.toISOString() !== baseUpdatedAt) {
        throw Object.assign(new Error("conflict"), { code: 409 });
      }
      await tx.user.update({
        where: { id: auth!.auth!.userId },
        data: {
          name: data.name,
          displayName: data.displayName ?? data.name,
          email: data.email,
          ...(data.language ? { language: data.language } : {}),
          ...(data.theme ? { theme: data.theme } : {}),
          ...(data.avatar ? { avatar: data.avatar } : {}),
        },
      });
      // SELECT after UPDATE — return exactly what is stored (T-S71-1)
      return tx.user.findUnique({
        where: { id: auth!.auth!.userId },
        select: {
          id: true,
          name: true,
          displayName: true,
          email: true,
          avatar: true,
          language: true,
          theme: true,
          role: true,
          emailVerified: true,
          twoFactorEnabled: true,
          lastLoginAt: true,
          updatedAt: true,
        },
      });
    });

    // Immediate invalidation of every user-namespaced cache (T-S21-4)
    await cacheInvalidateUser("profile", auth.auth.userId);
    await cacheInvalidateUser("settings", auth.auth.userId);
    await cacheInvalidateUser("search", auth.auth.userId);

    await audit({
      userId: auth.auth.userId,
      event: "profile_update",
      ip: clientIp(request),
      userAgent: request.headers.get("user-agent"),
      meta: { fields: "name/email/language/theme/avatar" },
    });

    return Response.json({ ok: true, profile: updated }, { headers: { "cache-control": "no-store" } });
  } catch (e) {
    const code = (e as { code?: number }).code;
    if (code === 409) {
      const fresh = await db.user.findUnique({ where: { id: auth.auth.userId } });
      return Response.json(
        { ok: false, error: { code: "conflict" }, profile: fresh },
        { status: 409, headers: { "cache-control": "no-store" } },
      );
    }
    if (code === 404) return errorResponse(404, "profile_missing");
    // unique email collision → uniform message, no DB internals (T-S47-3)
    return errorResponse(409, "email_unavailable");
  }
}

/** Avatar update shares the same store; used by T-S19-2. */
export async function POST(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);
  let body: { avatar?: string };
  try {
    body = (await request.json()) as { avatar?: string };
  } catch {
    return errorResponse(400, "invalid_json");
  }
  if (!body.avatar || typeof body.avatar !== "string" || body.avatar.length > 512 || !/^\/uploads\/[\w-]+\.(jpg|png|webp)$/.test(body.avatar)) {
    return errorResponse(400, "invalid_avatar");
  }
  const updated = await db.user.update({
    where: { id: auth.auth.userId },
    data: { avatar: body.avatar },
    select: { id: true, avatar: true, updatedAt: true },
  });
  await cacheInvalidateUser("profile", auth.auth.userId);
  await audit({ userId: auth.auth.userId, event: "avatar_change", ip: clientIp(request) });
  return Response.json({ ok: true, profile: updated }, { headers: { "cache-control": "no-store" } });
}
