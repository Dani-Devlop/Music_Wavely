/**
 * T-S25-1..3, T-S52-1..6, T-S02-1..4, T-R02-1..4 — Telegram WebApp initData
 * validation + token-never-to-client (DAST sweep over all API endpoints).
 * The test bot token lives only in the gitignored .env — never in code.
 */
import { beforeAll, describe, expect, test } from "bun:test";
import { createHmac } from "crypto";

const BASE = "http://localhost:3000";
let BOT_TOKEN = "";

/** unique simulated client IP per run — keeps rate buckets separate between runs */
const IP = `10.${(Date.now() >> 16) & 255}.${(Date.now() >> 8) & 255}.${Date.now() & 255}`;
const withIp = (headers: Record<string, string> = {}): Record<string, string> => ({ "x-forwarded-for": IP, ...headers });

beforeAll(() => {
  BOT_TOKEN = process.env.BOT_TOKEN ?? "";
  if (!BOT_TOKEN) throw new Error("BOT_TOKEN must be present in .env for initData tests");
});

/** Build a spec-correct initData signed with the test token. */
function buildInitData(opts: { user: object; authDate: number; queryId?: string }): { initData: string; hash: string } {
  const params = new URLSearchParams();
  params.set("auth_date", String(opts.authDate));
  if (opts.queryId) params.set("query_id", opts.queryId);
  params.set("user", JSON.stringify(opts.user));
  const dataCheckString = [...params.entries()].map(([k, v]) => `${k}=${v}`).sort().join("\n");
  const secretKey = createHmac("sha256", "WebAppData").update(BOT_TOKEN).digest();
  const hash = createHmac("sha256", secretKey).update(dataCheckString).digest("hex");
  params.set("hash", hash);
  return { initData: params.toString(), hash };
}

describe("S52 Telegram initData validation", () => {
  test("T-S52-1 / T-S25-1: valid initData verifies and yields user.id", async () => {
    const { validateInitData } = await import("@/lib/wavely/server/telegram");
    const { initData } = buildInitData({ user: { id: 777001, first_name: "Ali" }, authDate: Math.floor(Date.now() / 1000), queryId: "AAH" });
    const verdict = validateInitData(initData);
    expect(verdict.ok).toBe(true);
    expect(verdict.user?.id).toBe(777001);
    expect(verdict.queryId).toBe("AAH");
  });

  test("T-S52-1: tampered payload fails HMAC", async () => {
    const { validateInitData } = await import("@/lib/wavely/server/telegram");
    const { initData } = buildInitData({ user: { id: 777002, first_name: "Sara" }, authDate: Math.floor(Date.now() / 1000) });
    const tampered = initData.replace("Sara", "Mallory");
    const verdict = validateInitData(tampered);
    expect(verdict.ok).toBe(false);
    expect(verdict.code).toBe(401);
  });

  test("T-S52-2: auth_date older than 5 minutes is rejected (replay)", async () => {
    const { validateInitData } = await import("@/lib/wavely/server/telegram");
    const { initData } = buildInitData({ user: { id: 777003 }, authDate: Math.floor(Date.now() / 1000) - 301 });
    const verdict = validateInitData(initData);
    expect(verdict.ok).toBe(false);
    expect(verdict.reason).toBe("replayed-auth-date");
  });

  test("T-S52-4: user.id is the only trusted identity; bad user payload rejected", async () => {
    const { validateInitData } = await import("@/lib/wavely/server/telegram");
    const { initData } = buildInitData({ user: { id: "not-a-number" }, authDate: Math.floor(Date.now() / 1000) });
    const verdict = validateInitData(initData);
    expect(verdict.ok).toBe(false);
    expect(verdict.reason).toBe("bad-user-id");
  });

  test("T-S52-5: missing query_id fails the WebApp origin check", async () => {
    const { validateInitData, checkWebAppOrigin } = await import("@/lib/wavely/server/telegram");
    const { initData } = buildInitData({ user: { id: 777004 }, authDate: Math.floor(Date.now() / 1000) });
    const verdict = validateInitData(initData);
    expect(checkWebAppOrigin(verdict, null)).toBe(false);
  });
});

describe("S25 WebApp auth endpoint + token secrecy", () => {
  test("T-S25-1 (HTTP): initData login issues an HttpOnly session cookie", async () => {
    const { initData } = buildInitData({ user: { id: 777005, first_name: "WebApp" }, authDate: Math.floor(Date.now() / 1000), queryId: "Q1" });
    const res = await fetch(`${BASE}/api/auth/telegram`, {
      method: "POST",
      headers: withIp({ "content-type": "application/json" }),
      body: JSON.stringify({ initData }),
    });
    expect(res.status).toBe(200);
    const setCookies = res.headers.getSetCookie?.() ?? [];
    const sessionCookie = setCookies.find((c) => c.startsWith("wavely_session=") || c.startsWith("__Host-wavely_session="));
    expect(sessionCookie).toBeTruthy();
    expect(sessionCookie).toContain("HttpOnly");
    expect(sessionCookie).toContain("SameSite=Lax");
    const body = (await res.json()) as { ok: boolean; user: { telegramId: string }; csrfToken: string };
    expect(body.ok).toBe(true);
    expect(body.user.telegramId).toBe("777005");
  });

  test("T-S52-2 (HTTP): replayed initData rejected at the endpoint", async () => {
    const { initData } = buildInitData({ user: { id: 777006 }, authDate: Math.floor(Date.now() / 1000) - 600, queryId: "Q2" });
    const res = await fetch(`${BASE}/api/auth/telegram`, {
      method: "POST",
      headers: withIp({ "content-type": "application/json" }),
      body: JSON.stringify({ initData }),
    });
    expect(res.status).toBe(401);
  });

  test("T-S25-2 / T-S52-3 (CRITICAL, DAST): no API response ever contains a token", async () => {
    const endpoints = [
      "/api/health",
      "/api/ready",
      "/api/profile",
      "/api/auth/sessions",
      "/api/auth/telegram",
      "/api/cache",
      "/api/search?q=test",
      "/api/metrics",
      "/api/lyrics?trackId=t1",
      "/api/chat",
      "/api/translate",
    ];
    const pattern = /\b\d{8,12}:AA[\w-]{20,}\b/;
    for (const ep of endpoints) {
      const res = await fetch(`${BASE}${ep}`);
      const text = await res.text();
      expect(pattern.test(text), `token leak via ${ep}`).toBe(false);
      expect(text).not.toContain(BOT_TOKEN);
    }
  });

  test("T-S25-3: the nine WebApp essentials are present in the app shell", async () => {
    // login / 2FA / profile / sessions / cache / playback / search / playlist / account management
    const accountSrc = await Bun.file("src/components/wavely/views/account-view.tsx").text();
    const settingsSrc = await Bun.file("src/components/wavely/views/settings-view.tsx").text();
    const searchSrc = await Bun.file("src/components/wavely/views/search-view.tsx").text();
    const librarySrc = await Bun.file("src/components/wavely/views/library-view.tsx").text();
    expect(accountSrc).toContain("Sessions & devices"); // sessions
    expect(accountSrc).toContain("Account management"); // account management
    expect(accountSrc).toContain("twoFactor"); // 2FA controls
    expect(accountSrc).toContain("Cookies & site data"); // cookies
    expect(settingsSrc).toContain("Streaming cache"); // cache
    expect(searchSrc).toContain("Search music"); // search
    expect(librarySrc).toContain("playlists"); // playlists + library playback
    expect(librarySrc.length).toBeGreaterThan(0);
    // playback is the app's core player bar
    const playerSrc = await Bun.file("src/components/wavely/player-bar.tsx").text();
    expect(playerSrc).toContain("play");
  });
});
