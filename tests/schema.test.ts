/**
 * T-S15-1..2, T-R15-1..2 — database schema: the 9 core tables exist and
 * is_mixed defaults to false.
 */
import { describe, expect, test } from "bun:test";

describe("S15 schema", () => {
  test("T-S15-1 / T-R15-1: all 9 core tables exist in the SQLite database", async () => {
    const { db } = await import("@/lib/db");
    const tables = (await db.$queryRaw<{ name: string }[]>`SELECT name FROM sqlite_master WHERE type='table'`).map((t) => t.name);
    for (const t of ["User", "Session", "UserSetting", "Download", "Room", "RoomListener", "Playlist", "PlaylistTrack", "BotConfig"]) {
      expect(tables, `missing table ${t}`).toContain(t);
    }
  });

  test("T-S15-2 / T-R15-2: is_mixed defaults to false on insert without it", async () => {
    const { db } = await import("@/lib/db");
    const user = await db.user.create({ data: { email: `schematest${Date.now()}@wavely.test`, name: "Schema" } });
    const pl = await db.playlist.create({ data: { userId: user.id, name: "plain", shareToken: `sc-${Date.now()}` } });
    expect(pl.isMixed).toBe(false);
    await db.user.delete({ where: { id: user.id } });
  });

  test("T-S15-1b: security tables exist (sessions/audit/csrf/cache/export)", async () => {
    const { db } = await import("@/lib/db");
    const tables = (await db.$queryRaw<{ name: string }[]>`SELECT name FROM sqlite_master WHERE type='table'`).map((t) => t.name);
    for (const t of ["AuditLog", "LoginAttempt", "EmailVerification", "PasswordReset", "RememberToken", "RecoveryCode", "CsrfToken", "CacheEntry", "DataExport", "AgentUsage", "LyricsCache", "DeviceAlert"]) {
      expect(tables, `missing table ${t}`).toContain(t);
    }
  });
});
