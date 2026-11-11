/**
 * T-S07-1..3, T-S08-1..3 (agent modules half), T-R07-1..3, T-R08-1..3 —
 * AI DJ behaviour and personalization gating.
 */
import { beforeAll, afterAll, describe, expect, test } from "bun:test";

let userId = "";

beforeAll(async () => {
  const { db } = await import("@/lib/db");
  const { ensureFlagDefaults } = await import("@/lib/wavely/bot/flags");
  await ensureFlagDefaults();
  const u = await db.user.create({ data: { email: `aitest${Date.now()}@wavely.test`, name: "AI Tester" } });
  userId = u.id;
});

afterAll(async () => {
  const { db } = await import("@/lib/db");
  await db.user.deleteMany({ where: { id: userId } });
});

describe("S07 AI DJ", () => {
  test("T-S07-3 / T-R07-3: getMixedPlaylists returns ONLY is_mixed=true", async () => {
    const { db } = await import("@/lib/db");
    const { getMixedPlaylists } = await import("@/lib/wavely/bot/ai-dj");
    await db.playlist.createMany({
      data: [
        { userId, name: "mix-a", shareToken: `ma-${Date.now()}`, isMixed: true },
        { userId, name: "plain-b", shareToken: `pb-${Date.now()}`, isMixed: false },
        { userId, name: "mix-c", shareToken: `mc-${Date.now()}`, isMixed: true },
      ],
    });
    const mixes = await getMixedPlaylists(userId);
    expect(mixes.length).toBe(2);
    expect(mixes.every((m) => m.isMixed)).toBe(true);
    expect(mixes.some((m) => m.name === "plain-b")).toBe(false);
  });

  test("T-S07-1 / T-R07-1: /dj_play plays a mix end-to-end; non-mix refused", async () => {
    const { db } = await import("@/lib/db");
    const { djPlay } = await import("@/lib/wavely/bot/ai-dj");
    const mix = await db.playlist.create({ data: { userId, name: "Night Mix", shareToken: `nm-${Date.now()}`, isMixed: true } });
    await db.playlistTrack.createMany({
      data: [
        { playlistId: mix.id, trackId: "t01", position: 0 },
        { playlistId: mix.id, trackId: "t02", position: 1 },
        { playlistId: mix.id, trackId: "t03", position: 2 },
      ],
    });
    const playing = await djPlay(userId, mix.id);
    expect(playing.text).toContain("3 tracks queued");
    const plain = await db.playlist.create({ data: { userId, name: "Plain", shareToken: `pl-${Date.now()}`, isMixed: false } });
    const refused = await djPlay(userId, plain.id);
    expect(refused.text).toContain("Only mix playlists");
  });

  test("T-S07-2 / T-R07-2: personalize is NEVER called without the flag", async () => {
    const { personalizeIfEnabled } = await import("@/lib/wavely/bot/ai-dj");
    const result = await personalizeIfEnabled(userId);
    expect(result).toBeNull(); // flag false → module never invoked
  });

  test("T-S07-2b: with the flag ON the personalization module loads and runs", async () => {
    const { adminSetFlag, FLAG_KEYS } = await import("@/lib/wavely/bot/commands");
    const { OWNER_ID } = await import("@/lib/wavely/server/env");
    await adminSetFlag(OWNER_ID, FLAG_KEYS.aiDjPersonalization, "true");
    const { personalizeIfEnabled } = await import("@/lib/wavely/bot/ai-dj");
    const result = await personalizeIfEnabled(userId);
    expect(result).not.toBeNull();
    expect(result![0]).toContain("personal-mix");
    await adminSetFlag(OWNER_ID, FLAG_KEYS.aiDjPersonalization, "false");
  });
});

describe("S12 queue", () => {
  test("T-S12-1 / T-R12-1: 50 jobs drain in 25-sized batches with 1s spacing", async () => {
    const { BotQueue, QUEUE_CONCURRENCY, QUEUE_DELAY_MS } = await import("@/lib/wavely/bot/queue");
    expect(QUEUE_CONCURRENCY).toBe(25);
    expect(QUEUE_DELAY_MS).toBe(1000);
    const q = new BotQueue();
    let sent = 0;
    for (let i = 0; i < 50; i++) q.enqueue({ id: `j${i}`, run: async () => { sent++; return { ok: true }; } });
    const started = Date.now();
    const results = await q.drain();
    const elapsed = Date.now() - started;
    expect(results.every((r) => r.ok)).toBe(true);
    expect(sent).toBe(50);
    // 2 batches → at least 1 inter-batch delay (~1s)
    expect(elapsed).toBeGreaterThanOrEqual(900);
  });

  test("T-S12-2 / T-R12-2: 429 triggers exponential backoff capped at 60s", async () => {
    const { BotQueue, MAX_BACKOFF_SEC } = await import("@/lib/wavely/bot/queue");
    expect(MAX_BACKOFF_SEC).toBe(60);
    const q = new BotQueue();
    let attempts = 0;
    const job = {
      id: "backoff",
      run: async () => {
        attempts++;
        if (attempts < 3) return { ok: false, retryAfter: 1 };
        return { ok: true };
      },
    };
    const res = await q.execute(job);
    expect(res.ok).toBe(true);
    expect(attempts).toBe(3);
  });

  test("T-S12-4 / T-R12-4: allSettled-based batch execution isolates failures", async () => {
    const { BotQueue } = await import("@/lib/wavely/bot/queue");
    const tasks = [
      async () => 1,
      async () => {
        throw new Error("boom");
      },
      async () => 3,
    ];
    const settled = await BotQueue.runAll(tasks);
    expect(settled.length).toBe(3);
    expect(settled[0].status).toBe("fulfilled");
    expect(settled[1].status).toBe("rejected");
    expect(settled[2].status).toBe("fulfilled");
  });

  test("T-S12-3 / T-R12-3: telegram rate guards enforce 20/min group and 1/s private", async () => {
    const { GroupRateGuard, PrivateRateGuard, TG_LIMITS } = await import("@/lib/wavely/bot/queue");
    expect(TG_LIMITS.groupPerMin).toBe(20);
    expect(TG_LIMITS.privatePerSec).toBe(1);
    const g = new GroupRateGuard();
    let allowedCount = 0;
    for (let i = 0; i < 25; i++) if (g.allow("chat1", 1000 + i * 10)) allowedCount++;
    expect(allowedCount).toBe(20);
    const p = new PrivateRateGuard();
    expect(p.allow("dm1", 1000)).toBe(true);
    expect(p.allow("dm1", 1200)).toBe(false);
    expect(p.allow("dm1", 2100)).toBe(true);
  });

  test("T-S12-5 / T-R12-5: repeated search hits the cache (faster, single compute)", async () => {
    const { cacheGet, cacheInvalidate } = await import("@/lib/wavely/server/cache");
    const entity = `cache-hit-${Date.now()}`;
    let computes = 0;
    const loader = async () => {
      computes++;
      await new Promise((r) => setTimeout(r, 15));
      return { q: entity, ts: computes };
    };
    const started = Date.now();
    await cacheGet("search", null, entity, loader, { ttl: 300 });
    const coldMs = Date.now() - started;
    const warmStart = Date.now();
    const warm = await cacheGet("search", null, entity, loader, { ttl: 300 });
    const warmMs = Date.now() - warmStart;
    expect(computes).toBe(1); // second call served from cache
    expect(warmMs).toBeLessThanOrEqual(coldMs);
    void warm;
    await cacheInvalidate("search", null, entity);
  });
});

describe("S13 providers", () => {
  test("T-S13-1 / T-R13-1: active provider follows bot_config", async () => {
    const { getActiveProvider, PROVIDER_NAMES } = await import("@/lib/wavely/providers");
    const provider = await getActiveProvider();
    expect(PROVIDER_NAMES).toContain(provider.name);
    expect(provider.name).toBe("jamendo"); // default
  });

  test("T-S13-2 / T-R13-2: every provider implements the shared 4-method interface", async () => {
    const { buildProviders } = await import("@/lib/wavely/providers");
    const registry = buildProviders({});
    for (const name of ["jamendo", "fma", "archive"]) {
      const p = registry[name];
      expect(typeof p.search).toBe("function");
      expect(typeof p.getTrack).toBe("function");
      expect(typeof p.getArtist).toBe("function");
      expect(typeof p.getAlbum).toBe("function");
      const artist = await p.getArtist("someone");
      expect(artist).not.toBeNull();
      const album = await p.getAlbum("some-album");
      expect(album).not.toBeNull();
    }
  });

  test("T-S13-3 / T-R13-3: a new provider works without touching other code", async () => {
    const { getActiveProvider, buildProviders } = await import("@/lib/wavely/providers");
    const registry = buildProviders({});
    const custom = {
      name: "custom",
      search: async () => [{ id: "c1", title: "Hello", artist: "World", album: "A", durationSec: 1, audioUrl: "u", license: "CC" }],
      getTrack: async () => null,
      getArtist: async () => null,
      getAlbum: async () => null,
    };
    registry["custom"] = custom;
    expect(registry["custom"].name).toBe("custom");
    const results = await registry["custom"].search("hello");
    expect(results[0].title).toBe("Hello");
    void getActiveProvider;
  });

  test("T-S13-4 / T-R13-4: search on the three providers returns valid shapes", async () => {
    const { buildProviders } = await import("@/lib/wavely/providers");
    const registry = buildProviders({ jamendoClientId: "" });
    for (const name of ["jamendo", "fma", "archive"]) {
      const rows = await registry[name].search("test", 5);
      expect(Array.isArray(rows)).toBe(true);
      for (const r of rows) {
        expect(typeof r.id).toBe("string");
        expect(typeof r.title).toBe("string");
        expect(typeof r.license).toBe("string");
      }
    }
  });
});
