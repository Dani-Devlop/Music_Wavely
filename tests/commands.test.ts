/**
 * T-S09-1..5, T-S10-1..3, T-S11-1..3, T-S14-1..2,
 * T-R09-1..5, T-R10-1..3, T-R11-1..3, T-R14-1..2 — commands, language flow,
 * inline mode, force join.
 */
import { beforeAll, afterAll, describe, expect, test } from "bun:test";
import type { CommandContext } from "@/lib/wavely/bot/commands";

let userId = "";

async function mkCtx(overrides: Partial<CommandContext> = {}): Promise<CommandContext> {
  return {
    from: { id: userId, first_name: "Ali", last_name: "", username: "alitest" },
    chatId: userId,
    isGroup: false,
    ...overrides,
  };
}

beforeAll(async () => {
  const { db } = await import("@/lib/db");
  const { ensureFlagDefaults } = await import("@/lib/wavely/bot/flags");
  await ensureFlagDefaults();
  const stamp = Date.now();
  const u = await db.user.create({ data: { telegramId: `cmd-${stamp}`, email: `cmd-${stamp}@wavely.test`, name: "Ali" } });
  userId = u.telegramId!;
});

afterAll(async () => {
  const { db } = await import("@/lib/db");
  await db.user.deleteMany({ where: { telegramId: { startsWith: "cmd-" } } });
});

describe("S09 commands", () => {
  test("T-S09-1 / T-R09-1: /start for a new user shows the 5-language menu", async () => {
    const { dispatchCommand } = await import("@/lib/wavely/bot/commands");
    const ctx = await mkCtx({ from: { id: `fresh-${Date.now()}`, first_name: "New" } });
    const reply = await dispatchCommand(ctx, "/start");
    expect(reply.buttons?.length).toBe(5);
    expect(reply.buttons?.map((b) => b.label)).toEqual(["English", "فارسی", "Русский", "العربية", "Türkçe"]);
  });

  test("T-S09-2 / T-R09-2: /start for a returning user greets directly", async () => {
    const { dispatchCommand } = await import("@/lib/wavely/bot/commands");
    const reply = await dispatchCommand(await mkCtx(), "/start");
    expect(reply.buttons).toBeUndefined();
    expect(reply.text).toContain("Wavely");
  });

  test("T-S09-3 / T-R09-3: /me never emits an empty last_name line", async () => {
    const { meProfileText } = await import("@/lib/wavely/bot/commands");
    const text = meProfileText({ id: "1", first_name: "Ali", last_name: "", username: "alitest" });
    expect(text).not.toContain("Last name:");
    expect(text.split("\n").some((l) => l.trim() === "")).toBe(false);
    const withLast = meProfileText({ id: "1", first_name: "Ali", last_name: "Rezaei" });
    expect(withLast).toContain("Last name: Rezaei");
  });

  test("T-S09-4 / T-R09-4: all 8 public commands respond without error", async () => {
    const { PUBLIC_COMMANDS, dispatchCommand } = await import("@/lib/wavely/bot/commands");
    for (const cmd of PUBLIC_COMMANDS) {
      const reply = await dispatchCommand(await mkCtx(), cmd);
      expect(reply.text.length, `${cmd} produced an empty reply`).toBeGreaterThan(0);
    }
  });

  test("T-S09-5 / T-R09-5: /admin is owner-only", async () => {
    const { dispatchCommand } = await import("@/lib/wavely/bot/commands");
    const denied = await dispatchCommand(await mkCtx(), "/admin");
    expect(denied.text).toContain("only available to the bot owner");
    const { OWNER_ID } = await import("@/lib/wavely/server/env");
    const allowed = await dispatchCommand(await mkCtx({ from: { id: OWNER_ID, first_name: "Owner" } }), "/admin");
    expect(allowed.buttons?.some((b) => b.label === "Feature Flags")).toBe(true);
  });
});

describe("S10 language flow", () => {
  test("T-S10-1 / T-R10-1: language choice is persisted (users.language)", async () => {
    const { handleLanguageChoice } = await import("@/lib/wavely/bot/commands");
    const reply = await handleLanguageChoice(userId, "فارسی");
    expect(reply.text).toContain("language: فارسی");
    const { db } = await import("@/lib/db");
    const row = await db.user.findUnique({ where: { telegramId: userId } });
    expect(row?.language).toBe("fa");
  });

  test("T-S10-2 / T-R10-2: language applies immediately in bot replies", async () => {
    const { dispatchCommand } = await import("@/lib/wavely/bot/commands");
    const reply = await dispatchCommand(await mkCtx(), "/start");
    expect(reply.text).toContain("خوش آمدید"); // Persian welcome for fa
  });

  test("T-S10-3 / T-R10-3: cycling all 5 languages never errors", async () => {
    const { handleLanguageChoice, BOT_LANGUAGES } = await import("@/lib/wavely/bot/commands");
    for (const lang of BOT_LANGUAGES) {
      const reply = await handleLanguageChoice(userId, lang);
      expect(reply.text.length).toBeGreaterThan(0);
    }
  });
});

describe("S11 inline mode", () => {
  test("T-S11-1 / T-R11-1: inline query returns audio results with full captions + 4 buttons", async () => {
    const { telegramAnswerInlineArgs } = await import("@/lib/wavely/bot/inline");
    const args = await telegramAnswerInlineArgs("neon");
    expect(args.results.length).toBeGreaterThan(0);
    for (const r of args.results) {
      expect(r.type).toBe("audio");
      expect(r.caption).toContain("—");
      expect(r.caption).toContain("via Wavely");
      expect(r.buttons.map((b) => b.label)).toEqual(["👤 Artist Info", "💿 Album", "⬇️ Download", "🌐 Open in Mini App"]);
    }
    expect(args.cache_time).toBe(300);
  });

  test("T-S11-2 / T-R11-2: results capped at 50 with next_offset", async () => {
    const { buildInlineResults, INLINE_MAX_RESULTS } = await import("@/lib/wavely/bot/inline");
    expect(INLINE_MAX_RESULTS).toBe(50);
    // 'e' matches most of the catalogue — paging must never exceed 50 total
    let offset = 0;
    let total = 0;
    let guard = 0;
    for (;;) {
      const { results, next_offset } = await buildInlineResults("e", offset);
      total += results.length;
      if (!next_offset || guard++ > 10) break;
      offset = Number(next_offset);
    }
    expect(total).toBeLessThanOrEqual(50);
  });

  test("T-S11-3 / T-R11-3: facet parsing and Open-in-Mini-App button present", async () => {
    const { parseInlineQuery, inlineButtons } = await import("@/lib/wavely/bot/inline");
    expect(parseInlineQuery("Vector Dreams | artist").facet).toBe("artist");
    expect(parseInlineQuery("synthwave | genre").facet).toBe("genre");
    expect(parseInlineQuery("2019 | year").facet).toBe("year");
    expect(parseInlineQuery("just a song").facet).toBeUndefined();
    expect(inlineButtons().some((b) => b.label.includes("Open in Mini App"))).toBe(true);
  });
});

describe("S14 force join", () => {
  test("T-S14-1 / T-R14-1: gate is a no-op when force_join_enabled=false", async () => {
    const { dispatchCommand } = await import("@/lib/wavely/bot/commands");
    const reply = await dispatchCommand(await mkCtx(), "/help");
    expect(reply.text).not.toContain("join our channel");
  });

  test("T-S14-2 / T-R14-2: gate redirects non-members when enabled", async () => {
    const { adminSetFlag, FLAG_KEYS, dispatchCommand } = await import("@/lib/wavely/bot/commands");
    const { OWNER_ID } = await import("@/lib/wavely/server/env");
    await adminSetFlag(OWNER_ID, FLAG_KEYS.forceJoin, "true");
    const ctx = await mkCtx({ from: { id: `notmember-${Date.now()}`, first_name: "Ghost" } });
    const reply = await dispatchCommand(ctx, "/help");
    expect(reply.text).toContain("join our channel first");
    expect(reply.text).toContain("https://t.me/My_Hellz");
    // restore
    await adminSetFlag(OWNER_ID, FLAG_KEYS.forceJoin, "false");
  });
});
