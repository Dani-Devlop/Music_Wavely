/**
 * T-S01-1..5, T-S16-1, T-R01-1..5, T-R16-1 — MVP scope: no payment code, AI
 * flags off, AI DJ basic active, mini-app online-only, deploy script contract.
 * Actual tgcloud deployment (T-S01-1/T-S16-1/T-R01-1/T-R16-1) is executed by
 * scripts/deploy-tgcloud.sh — BLOCKED in this sandbox (no tgcloud account);
 * the script contract is verified here.
 */
import { describe, expect, test } from "bun:test";

describe("S01 MVP scope", () => {
  test("T-S01-2 / T-R01-2: no payment/subscription code in the repo", async () => {
    const proc = Bun.spawnSync(["git", "ls-files"], { cwd: process.cwd() });
    const files = proc.stdout.toString().split("\n").filter(Boolean);
    const pattern = /\b(stripe|paypal|payment_intent|checkout_session|subscription_id)\b/i;
    for (const f of files) {
      if (!/\.(ts|tsx|js|jsx)$/.test(f)) continue;
      if (f.startsWith("tests/") || f.startsWith("examples/") || f.startsWith("skills/")) continue;
      const text = await Bun.file(f).text();
      expect(pattern.test(text), `payment code in ${f}`).toBe(false);
    }
  });

  test("T-S01-3 / T-R01-3: all three AI flags default false", async () => {
    const { aiFlagsAllFalse, FLAG_KEYS, getFlag } = await import("@/lib/wavely/bot/flags");
    const flags = await aiFlagsAllFalse();
    expect(flags.ai_search).toBe(false);
    expect(flags.audio_recognition).toBe(false);
    expect(flags.ai_dj_personalization).toBe(false);
    expect(await getFlag(FLAG_KEYS.aiSearch)).toBe("false");
  });

  test("T-S01-3b: gated modules never load with flags off (T-S08-1 / T-R08-1)", async () => {
    const { loadGatedModules } = await import("@/lib/wavely/bot/flags");
    const modules = await loadGatedModules();
    expect(modules.aiSearch).toBeNull();
    expect(modules.audioRecognize).toBeNull();
    expect(modules.aiDjPersonalization).toBeNull();
  });

  test("T-S01-4 / T-R01-4: /dj lists at least one is_mixed playlist", async () => {
    const { db } = await import("@/lib/db");
    const user = await db.user.create({ data: { email: `dj${Date.now()}@wavely.test`, name: "DJ Tester" } });
    await db.playlist.create({ data: { userId: user.id, name: "Wavely Weekly Mix", shareToken: `mix-${Date.now()}`, isMixed: true } });
    const { getMixedPlaylists } = await import("@/lib/wavely/bot/ai-dj");
    const mixes = await getMixedPlaylists(user.id);
    expect(mixes.length).toBeGreaterThanOrEqual(1);
    expect(mixes.every((m) => m.isMixed)).toBe(true);
    await db.user.delete({ where: { id: user.id } });
  });

  test("T-S01-5 / T-R01-5: mini-app is online-only — no paid/offline-storefront UI", async () => {
    const appShell = await Bun.file("src/components/wavely/app-shell.tsx").text();
    const settings = await Bun.file("src/components/wavely/views/settings-view.tsx").text();
    expect(appShell.toLowerCase()).not.toContain("purchase");
    expect(settings.toLowerCase()).not.toContain("stripe");
    // financial section absent while music sections present
    expect(settings).toContain("Streaming");
  });
});

describe("S08 flag governance", () => {
  test("T-S08-2 / T-R08-2: bot_config rows exist with value 'false'", async () => {
    const { db } = await import("@/lib/db");
    const { ensureFlagDefaults } = await import("@/lib/wavely/bot/flags");
    await ensureFlagDefaults();
    const rows = await db.botConfig.findMany({ where: { key: { in: ["ai_search_enabled", "audio_recognition_enabled", "ai_dj_personalization_enabled"] } } });
    expect(rows.length).toBe(3);
    for (const r of rows) expect(r.value).toBe("false");
  });

  test("T-S08-3 / T-R08-3: non-owner cannot flip flags; owner can", async () => {
    const { adminSetFlag, FLAG_KEYS } = await import("@/lib/wavely/bot/commands");
    const denied = await adminSetFlag("not-the-owner", FLAG_KEYS.aiSearch, "true");
    expect(denied.text).toContain("owner only");
    // ensure the flag was NOT flipped
    const { getFlag } = await import("@/lib/wavely/bot/flags");
    expect(await getFlag(FLAG_KEYS.aiSearch)).toBe("false");
    const { OWNER_ID } = await import("@/lib/wavely/server/env");
    const allowed = await adminSetFlag(OWNER_ID, FLAG_KEYS.aiSearch, "true");
    expect(allowed.text).toContain("→ true");
    // restore default
    await adminSetFlag(OWNER_ID, FLAG_KEYS.aiSearch, "false");
    expect(await getFlag(FLAG_KEYS.aiSearch)).toBe("false");
  });
});

describe("S16 / R16 deployment contract", () => {
  test("T-S16-1 / T-R16-1 (BLOCKED-execution, script verified): deploy script uses env tokens only", async () => {
    const script = await Bun.file("scripts/deploy-tgcloud.sh").text();
    expect(script).toContain("TGCLI_TOKEN:?TGCLI_TOKEN");
    expect(script).toContain("BOT_TOKEN:?BOT_TOKEN");
    expect(script).toContain("tgcloud");
    expect(script).toContain("migrate");
    // no literal token material
    expect(/\b\d{8,12}:AA[\w-]{20,}\b/.test(script)).toBe(false);
    expect(/app\d+:[\w]{20,}/.test(script)).toBe(false);
    // BLOCKED note: actual `npx tgcloud push` requires tgcloud credentials that
    // are <REDACTED> and unavailable in this sandbox — the script is ready.
  });
});
