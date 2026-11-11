/**
 * S27 — Search API: relevance ranking over the seeded catalogue.
 * The response deliberately contains NO origin/badge fields for track rows
 * (T-S27-1: the local/online badge requirement is absolute). Cache lives in
 * the "search" namespace and is invalidated on library changes (T-S21-x).
 */
import { guardRate, errorResponse, clientIp } from "@/lib/wavely/server/api-guard";
import { cacheGet, cacheInvalidateUser } from "@/lib/wavely/server/cache";
import { sanitizeSearchInput } from "@/lib/wavely/server/validation";
import { getCatalogue, rankCatalogue, type CatalogueFacet } from "@/lib/wavely/server/catalogue";
import { audit } from "@/lib/wavely/server/audit";

interface SearchRow {
  id: string;
  title: string;
  artist: string;
  album: string;
  duration: number;
}

export async function GET(request: Request) {
  const rate = guardRate(request, "search", null);
  if (!rate.ok) {
    const res = errorResponse(rate.status, rate.code, rate.message);
    res.headers.set("retry-after", rate.message ?? "60");
    return res;
  }
  const url = new URL(request.url);
  const rawQuery = url.searchParams.get("q") ?? "";
  const filterParam = (url.searchParams.get("filter") ?? "all") as CatalogueFacet;
  const allowed: CatalogueFacet[] = ["all", "title", "artist", "album", "genre", "year"];
  const filter = allowed.includes(filterParam) ? filterParam : "all";
  const q = sanitizeSearchInput(rawQuery);
  if (!q) return Response.json({ ok: true, results: [] }, { headers: { "cache-control": "no-store" } });

  const results = await cacheGet("search", null, `${filter}:${q}`, async () => {
    const catalogue = await getCatalogue();
    const ranked = await rankCatalogue(q, filter, catalogue);
    return ranked.map((row) => ({
      id: row.id,
      title: row.title,
      artist: row.artist,
      album: row.album,
      duration: row.duration,
    }));
  }, { ttl: 300 });

  return Response.json({ ok: true, results }, { headers: { "cache-control": "no-store" } });
}

/** Library/source changes invalidate the search namespace (S27 invalidate rule). */
export async function DELETE(request: Request) {
  await cacheInvalidateUser("search", null);
  await audit({ event: "cache_cleared", ip: clientIp(request), meta: { scope: "search", reason: "library_change" } });
  return Response.json({ ok: true }, { headers: { "cache-control": "no-store" } });
}
