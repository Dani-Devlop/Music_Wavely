/**
 * Server-side catalogue ranking used by /api/search and the inline module.
 * Deterministic relevance: exact > prefix > contains, artist/album weighted.
 */
export interface CatalogueRow {
  id: string;
  title: string;
  artist: string;
  album: string;
  duration: number;
  year: number;
  genre: string;
}

export type CatalogueFacet = "all" | "artist" | "genre" | "year" | "title" | "album";

let cache: CatalogueRow[] | null = null;

export async function getCatalogue(): Promise<CatalogueRow[]> {
  if (cache) return cache;
  const { TRACKS } = await import("@/lib/wavely/data");
  cache = TRACKS.map((t) => ({
    id: t.id,
    title: t.title,
    artist: t.artist,
    album: t.album,
    duration: t.duration,
    year: t.year,
    genre: t.genre,
  }));
  return cache;
}

/** Test seam: replace the catalogue (used by load-test seeding). */
export function setCatalogue(rows: CatalogueRow[] | null) {
  cache = rows;
}

export function rankCatalogueSync(term: string, facet: CatalogueFacet = "all", rows: CatalogueRow[]): CatalogueRow[] {
  const needle = term.toLowerCase();
  const scored = rows.map((row) => {
    let score = 0;
    const title = row.title.toLowerCase();
    const artist = row.artist.toLowerCase();
    const album = row.album.toLowerCase();
    const genre = row.genre.toLowerCase();
    if (title === needle) score += 100;
    else if (title.startsWith(needle)) score += 80;
    else if (title.includes(needle)) score += 50;
    if (artist === needle) score += 60;
    else if (artist.startsWith(needle)) score += 40;
    else if (artist.includes(needle)) score += 20;
    if (album.includes(needle)) score += 10;
    if (genre.includes(needle)) score += 6;
    if (String(row.year) === needle) score += 30;
    if (facet === "title") score = title.includes(needle) ? score : 0;
    if (facet === "artist") score = artist.includes(needle) ? score + 30 : 0;
    if (facet === "album") score = album.includes(needle) ? score + 30 : 0;
    if (facet === "genre") score = genre.includes(needle) ? score + 30 : 0;
    if (facet === "year") score = String(row.year) === needle ? score + 30 : 0;
    return { row, score };
  });
  return scored
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 50)
    .map(({ row }) => row);
}

/** Async variant — self-loads the catalogue when not provided. */
export async function rankCatalogue(term: string, facet: CatalogueFacet = "all", catalogue?: CatalogueRow[]): Promise<CatalogueRow[]> {
  const rows = catalogue ?? (await getCatalogue());
  return rankCatalogueSync(term, facet, rows);
}
