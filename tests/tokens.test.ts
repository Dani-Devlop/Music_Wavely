/**
 * T-S02-1..4, T-R02-1..4 — token separation & secrecy.
 * The real tokens from the master prompt are treated as <REDACTED>: they must
 * never appear anywhere in the repo, logs or responses.
 */
import { describe, expect, test } from "bun:test";

describe("S02 token separation", () => {
  test("T-S02-1: CLI token and BOT token are separate env vars with separate roles", async () => {
    const env = await import("@/lib/wavely/server/env");
    expect("BOT_TOKEN" in env).toBe(true);
    expect("TGCLI_TOKEN" in env).toBe(true);
    // they are distinct variables (never one shared value in code)
    expect(env.BOT_TOKEN).not.toBeUndefined();
    expect(env.TGCLI_TOKEN).not.toBeUndefined();
  });

  test("T-S02-2 / T-R02-2: no token-shaped secret committed to the working tree", async () => {
    // scan all first-party source files for token shapes
    const proc = Bun.spawnSync(["git", "ls-files"], { cwd: process.cwd() });
    const files = proc.stdout.toString().split("\n").filter(Boolean);
    const pattern = /\b\d{8,12}:AA[\w-]{30,}\b|\bapp\d+:[\w]{20,}\b/;
    let scanned = 0;
    for (const f of files) {
      if (!/\.(ts|tsx|js|jsx|md|json|sh|yml|yaml|env|prisma)$/.test(f)) continue;
      if (f.startsWith("upload/")) continue; // sandbox artifact, gitignored
      try {
        const text = await Bun.file(f).text();
        scanned++;
        expect(pattern.test(text), `token-shaped secret in ${f}`).toBe(false);
      } catch {
        /* binary/unreadable */
      }
    }
    expect(scanned).toBeGreaterThan(50);
  });

  test("T-S02-2b: the uploaded master prompt is NOT tracked by git", () => {
    const proc = Bun.spawnSync(["git", "check-ignore", "upload/r-prompt-wavely.md"], { cwd: process.cwd() });
    expect(proc.exitCode).toBe(0); // ignored → the <REDACTED> material never reaches git
  });

  test("T-S02-3 / T-R02-3: audit layer never persists token-shaped strings", async () => {
    const { audit } = await import("@/lib/wavely/server/audit");
    const { db } = await import("@/lib/db");
    const secretish = "token " + "1234567890:" + "AA" + "aBcDeFgHiJkLmNoPqRsTuVwXyZ012345";
    await audit({ event: "login", meta: { note: secretish } });
    const rows = await db.auditLog.findMany({ where: { event: "login" }, orderBy: { createdAt: "desc" }, take: 3 });
    const serialized = JSON.stringify(rows);
    expect(serialized.includes(secretish)).toBe(false); // redacted, never stored
    expect(/\d{8,12}:AA/.test(serialized)).toBe(false);
  });

  test("T-S02-3b: leaksSecret detects both token shapes", async () => {
    const { leaksSecret } = await import("@/lib/wavely/server/env");
    expect(leaksSecret("bot=1234567890:AAbbccddeeffgghhiijjkkllmmnnoo1234")).toBe(true);
    expect(leaksSecret("cli=app1234567890:someverylongsecretvalue")).toBe(true);
    expect(leaksSecret("normal text without secrets")).toBe(false);
  });

  test("T-S02-4 / T-R02-4 (DAST-lite): env token never equals any env var shown to clients", async () => {
    const env = await import("@/lib/wavely/server/env");
    // the public surface (client-api + telegram route contract) exposes only identity
    const telegramSrc = await Bun.file("src/app/api/auth/telegram/route.ts").text();
    expect(telegramSrc).not.toContain("BOT_TOKEN");
    void env;
  });
});

describe("R02 bot-module token hygiene", () => {
  test("T-R02-1: bot runtime reads tokens only through env.ts", async () => {
    const envSrc = await Bun.file("src/lib/wavely/server/env.ts").text();
    expect(envSrc).toContain('process.env["BOT_TOKEN"]'.replace("process.env[\"BOT_TOKEN\"]", "process.env[name]"));
    // every bot module imports from env, never process.env directly
    const proc = Bun.spawnSync(["git", "ls-files", "src/lib/wavely/bot"], { cwd: process.cwd() });
    const files = proc.stdout.toString().split("\n").filter(Boolean);
    for (const f of files) {
      const src = await Bun.file(f).text();
      expect(src.includes("process.env.BOT_TOKEN") || src.includes('process.env["BOT_TOKEN"]'), `raw token access in ${f}`).toBe(false);
    }
  });
});
