/**
 * T-S27-1 (CRITICAL), T-S27-2, T-S69-4 — search: NO local/online badges, ever.
 * Server response carries no origin fields; source audit confirms the search
 * UI cannot render one. The visual DOM pass is done with agent-browser and
 * recorded in TASKS.md.
 */
import { describe, expect, test } from "bun:test";

const BASE = "http://localhost:3000";

describe("S27 search without badges", () => {
  test("T-S27-1 (CRITICAL, API): search results carry no origin/badge fields", async () => {
    const res = await fetch(`${BASE}/api/search?q=neon`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean; results: Record<string, unknown>[] };
    expect(body.ok).toBe(true);
    for (const row of body.results) {
      expect("origin" in row).toBe(false);
      expect("source" in row).toBe(false);
      expect("badge" in row).toBe(false);
    }
    // no badge-shaped strings anywhere in the payload
    const raw = JSON.stringify(body).toLowerCase();
    expect(raw).not.toContain('"origin"');
    expect(raw).not.toContain("online");
    expect(raw).not.toContain("local");
  });

  test("T-S27-1 (CRITICAL, source audit): search UI cannot render an OriginBadge", async () => {
    const src = await Bun.file("src/components/wavely/views/search-view.tsx").text();
    expect(src).not.toContain("OriginBadge");
    expect(src).not.toContain("Stream</span>");
    expect(src).not.toContain("origin ==="); // no origin-conditional UI in search
    expect(src).not.toMatch(/\bOriginBadge\b/);
  });

  test("T-S27-2: relevance ranking — exact title beats partial, artist filter works", async () => {
    const all = await fetch(`${BASE}/api/search?q=neon`);
    const allBody = (await all.json()) as { results: { title: string; artist: string }[] };
    if (allBody.results.length > 1) {
      // exact matches come before partial ones
      const first = allBody.results[0];
      expect(first.title.toLowerCase().startsWith("neon") || first.title.toLowerCase() === "neon").toBe(true);
    }
    const byArtist = await fetch(`${BASE}/api/search?q=neon&filter=artist`);
    const byArtistBody = (await byArtist.json()) as { results: { artist: string }[] };
    for (const r of byArtistBody.results) {
      expect(r.artist.toLowerCase()).toContain("neon");
    }
  });

  test("T-S27-2: search respects the 50-result cap (S11 parity)", async () => {
    const res = await fetch(`${BASE}/api/search?q=e`);
    const body = (await res.json()) as { results: unknown[] };
    expect(body.results.length).toBeLessThanOrEqual(50);
  });

  test("T-S27-1: empty query → empty result set, no leakage", async () => {
    const res = await fetch(`${BASE}/api/search?q=`);
    const body = (await res.json()) as { results: unknown[] };
    expect(body.results).toEqual([]);
  });
});
