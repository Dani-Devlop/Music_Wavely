/**
 * T-S19-1..5, T-S71-1..5 — Profile: server truth + refresh bug fix.
 * CRITICAL: change name → save → refresh → the NEW name must come back.
 *
 * External needs: dev server on http://localhost:3000 (integration, real HTTP).
 * The E2E UI half of T-S19-1 is additionally verified interactively with
 * agent-browser (click flow: Account → Edit → save → reload) — recorded in
 * TASKS.md.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";

const BASE = "http://localhost:3000";

let cookieHeader = "";
let csrfToken = "";
let baseUpdatedAt = "";
let userId = "";

const EMAIL = `profiletest${Date.now()}@wavely.test`;
const USERNAME = "profiletest" + String(Date.now()).slice(-6);
const PASSWORD = "xK9$mV2#pQ7!wZ4@"; // 16 chars, mixed classes, not in denylist

/** unique simulated client IP per run — keeps rate buckets separate between runs */
const IP = `10.${(Date.now() >> 16) & 255}.${(Date.now() >> 8) & 255}.${Date.now() & 255}`;
const withIp = (headers: Record<string, string> = {}): Record<string, string> => ({ "x-forwarded-for": IP, ...headers });

async function health(): Promise<boolean> {
  try {
    const res = await fetch(`${BASE}/api/health`);
    return res.status === 200;
  } catch {
    return false;
  }
}

beforeAll(async () => {
  if (!(await health())) {
    throw new Error("dev server not reachable — start it before running integration tests");
  }
  // 1. register (202 uniform response either way)
  await fetch(`${BASE}/api/auth/register`, {
    method: "POST",
    headers: withIp({ "content-type": "application/json" }),
    body: JSON.stringify({ email: EMAIL, username: USERNAME, password: PASSWORD, termsAccepted: true }),
  });
  // 2. login → session cookie + csrf
  const login = await fetch(`${BASE}/api/auth/login`, {
    method: "POST",
    headers: withIp({ "content-type": "application/json" }),
    body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
  });
  expect(login.status).toBe(200);
  const setCookie = login.headers.getSetCookie?.() ?? [login.headers.get("set-cookie") ?? ""];
  cookieHeader = setCookie
    .map((c) => c.split(";")[0])
    .filter((c) => c.startsWith("wavely_session="))
    .join("; ");
  const body = (await login.json()) as { ok: boolean; csrfToken: string; user: { id: string } };
  csrfToken = body.csrfToken;
  userId = body.user.id;
  // 3. fetch current profile for the optimistic base
  const me = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader }) });
  const meBody = (await me.json()) as { profile: { updatedAt: string } };
  baseUpdatedAt = meBody.profile.updatedAt;
});

describe("S71 profile refresh bug (CRITICAL)", () => {
  test("T-S71-1 / T-S19-1: change name → save → refresh → new name persists", async () => {
    const put = await fetch(`${BASE}/api/profile`, {
      method: "PUT",
      headers: withIp({
        "content-type": "application/json",
        cookie: cookieHeader,
        "x-csrf-token": csrfToken,
        "x-base-updated-at": baseUpdatedAt,
      }),
      body: JSON.stringify({ name: "TestUser123", email: EMAIL }),
    });
    expect(put.status).toBe(200);
    expect(put.headers.get("cache-control")).toBe("no-store"); // no client caching
    const putBody = (await put.json()) as { profile: { name: string } };
    expect(putBody.profile.name).toBe("TestUser123"); // SELECT-after-UPDATE

    // simulate a full refresh: brand-new GET requests (no client cache)
    const get1 = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader, "cache-control": "no-cache" }) });
    expect(get1.headers.get("cache-control")).toBe("no-store");
    const get1Body = (await get1.json()) as { profile: { name: string } };
    expect(get1Body.profile.name).toBe("TestUser123"); // ← the old bug returned the previous name here

    const get2 = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader }) });
    const get2Body = (await get2.json()) as { profile: { name: string } };
    expect(get2Body.profile.name).toBe("TestUser123");
  });

  test("T-S71-2 / T-S19-2: avatar + display name update path", async () => {
    const me = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader }) });
    const { profile } = (await me.json()) as { profile: { updatedAt: string; displayName: string | null } };
    const put = await fetch(`${BASE}/api/profile`, {
      method: "PUT",
      headers: withIp({
        "content-type": "application/json",
        cookie: cookieHeader,
        "x-csrf-token": csrfToken,
        "x-base-updated-at": profile.updatedAt,
      }),
      body: JSON.stringify({ name: "TestUser123", email: EMAIL, displayName: "Testy Display" }),
    });
    expect(put.status).toBe(200);
    const body = (await put.json()) as { profile: { displayName: string } };
    expect(body.profile.displayName).toBe("Testy Display");
    // after refresh the display name persists (server truth)
    const me2 = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader }) });
    const body2 = (await me2.json()) as { profile: { displayName: string } };
    expect(body2.profile.displayName).toBe("Testy Display");
  });

  test("T-S71-3 / T-S19-5: two concurrent writers with same base → optimistic conflict, last write wins", async () => {
    const me = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader }) });
    const { profile } = (await me.json()) as { profile: { updatedAt: string } };
    const base = profile.updatedAt;

    const putA = fetch(`${BASE}/api/profile`, {
      method: "PUT",
      headers: withIp({ "content-type": "application/json", cookie: cookieHeader, "x-csrf-token": csrfToken, "x-base-updated-at": base }),
      body: JSON.stringify({ name: "TabA Writer", email: EMAIL }),
    });
    const putB = fetch(`${BASE}/api/profile`, {
      method: "PUT",
      headers: withIp({ "content-type": "application/json", cookie: cookieHeader, "x-csrf-token": csrfToken, "x-base-updated-at": base }),
      body: JSON.stringify({ name: "TabB Writer", email: EMAIL }),
    });
    const [resA, resB] = await Promise.all([putA, putB]);
    const statuses = [resA.status, resB.status].sort();
    // exactly one wins, the other gets 409 conflict
    expect(statuses).toEqual([200, 409]);
    const winner = resA.status === 200 ? resA : resB;
    const winnerBody = (await winner.json()) as { profile: { name: string } };
    // the final server state equals the winning write
    const me2 = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader }) });
    const finalBody = (await me2.json()) as { profile: { name: string } };
    expect(finalBody.profile.name).toBe(winnerBody.profile.name);
  });

  test("T-S71-4 / T-S21-5: caches are invalidated on profile write (no stale Explore/Search data)", async () => {
    const { db } = await import("@/lib/db");
    const { cacheGet } = await import("@/lib/wavely/server/cache");

    // warm a DIRECT cache entity (separate from the API's own "me" entity)
    const warmed = await cacheGet("profile", userId, "warm-up", async () => ({ name: "STALE" }), { ttl: 300 });
    expect(warmed).toEqual({ name: "STALE" });

    // write profile through the API → invalidation runs inside PUT
    const me = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader }) });
    const { profile } = (await me.json()) as { profile: { updatedAt: string; name: string } };
    const put = await fetch(`${BASE}/api/profile`, {
      method: "PUT",
      headers: withIp({ "content-type": "application/json", cookie: cookieHeader, "x-csrf-token": csrfToken, "x-base-updated-at": profile.updatedAt }),
      body: JSON.stringify({ name: "Fresh Writer", email: EMAIL }),
    });
    expect(put.status).toBe(200);

    // every cached copy for this user must be gone (no stale rows for profile namespace)
    const rows = await db.cacheEntry.findMany({ where: { namespace: "profile", userId } });
    expect(rows.length).toBe(0);
  });

  test("T-S71-5: cross-device sync — a second session sees the saved name", async () => {
    // ensure a known fresh value first
    const me = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader }) });
    const { profile } = (await me.json()) as { profile: { updatedAt: string } };
    const put = await fetch(`${BASE}/api/profile`, {
      method: "PUT",
      headers: withIp({ "content-type": "application/json", cookie: cookieHeader, "x-csrf-token": csrfToken, "x-base-updated-at": profile.updatedAt }),
      body: JSON.stringify({ name: "Fresh Writer", email: EMAIL }),
    });
    expect(put.status).toBe(200);

    // second login = "other device"
    const login2 = await fetch(`${BASE}/api/auth/login`, {
      method: "POST",
      headers: withIp({ "content-type": "application/json" }),
      body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
    });
    expect(login2.status).toBe(200);
    const cookies2 = (login2.headers.getSetCookie?.() ?? [])
      .map((c) => c.split(";")[0])
      .filter((c) => c.startsWith("wavely_session="))
      .join("; ");
    const me2 = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookies2 }) });
    const body2 = (await me2.json()) as { profile: { name: string } };
    expect(body2.profile.name).toBe("Fresh Writer");
  });
});

describe("S19 profile API contract", () => {
  test("T-S19-4: revoke-all leaves zero live sessions for the user", async () => {
    const del = await fetch(`${BASE}/api/auth/sessions?all=1`, {
      method: "DELETE",
      headers: withIp({ cookie: cookieHeader, "x-csrf-token": csrfToken }),
    });
    expect(del.status).toBe(200);
    const body = (await del.json()) as { revoked: number };
    expect(body.revoked).toBeGreaterThanOrEqual(2); // both test sessions gone
    const me = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader }) });
    expect(me.status).toBe(401); // revoked everywhere
  });

  test("T-S19-3: security status fields are present (2FA/sessions/last login)", async () => {
    // re-login to obtain a fresh session for the remaining assertions
    const login = await fetch(`${BASE}/api/auth/login`, {
      method: "POST",
      headers: withIp({ "content-type": "application/json" }),
      body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
    });
    const body = (await login.json()) as { csrfToken: string };
    expect(login.status).toBe(200);
    cookieHeader = (login.headers.getSetCookie?.() ?? [])
      .map((c) => c.split(";")[0])
      .filter((c) => c.startsWith("wavely_session="))
      .join("; ");
    csrfToken = body.csrfToken;
    const me = await fetch(`${BASE}/api/profile`, { headers: withIp({ cookie: cookieHeader }) });
    const { profile } = (await me.json()) as { profile: { twoFactorEnabled: boolean; emailVerified: boolean; lastLoginAt: string | null } };
    expect(typeof profile.twoFactorEnabled).toBe("boolean");
    expect(typeof profile.emailVerified).toBe("boolean");
    expect(profile.lastLoginAt === null || typeof profile.lastLoginAt === "string").toBe(true);
  });
});

afterAll(async () => {
  // cleanup test user (data hygiene)
  try {
    const { db } = await import("@/lib/db");
    if (userId) await db.user.deleteMany({ where: { email: EMAIL } });
  } catch {
    /* cleanup best-effort */
  }
});
