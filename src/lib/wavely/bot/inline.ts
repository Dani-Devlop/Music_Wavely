/**
 * S11 / R11 — Inline mode: placeholder "Search music...", Audio/Photo results
 * with full captions + 4 action buttons, max 50 results, cache_time 300s,
 * next_offset pagination.
 */
import { sanitizeSearchInput } from "../server/validation";
import { rankCatalogue } from "../server/catalogue";

export const INLINE_PLACEHOLDER = "Search music...";
export const INLINE_MAX_RESULTS = 50;
export const INLINE_CACHE_TIME_SEC = 300;
export const INLINE_PAGE_SIZE = 20;

export interface InlineResult {
  id: string;
  type: "audio" | "photo";
  title: string;
  performer: string;
  caption: string;
  buttons: { label: string; data: string }[];
}

/** Inline query format: `@Wavely_MusicBot <name | artist | genre | year | en | fa>`. */
export function parseInlineQuery(query: string): { term: string; facet?: "artist" | "genre" | "year" } {
  const trimmed = query.trim();
  if (!trimmed) return { term: "" };
  const parts = trimmed.split("|").map((p) => p.trim());
  if (parts.length >= 2) {
    const facetRaw = parts[1].toLowerCase();
    const facet = facetRaw === "artist" || facetRaw === "genre" || facetRaw === "year" ? facetRaw : undefined;
    return { term: sanitizeSearchInput(parts[0]), facet };
  }
  return { term: sanitizeSearchInput(trimmed) };
}

function captionFor(title: string, artist: string, album: string, year: number): string {
  return `${title} — ${artist} • ${album} (${year}) • via Wavely`;
}

export function inlineButtons(): InlineResult["buttons"] {
  return [
    { label: "👤 Artist Info", data: "artist:info" },
    { label: "💿 Album", data: "album:open" },
    { label: "⬇️ Download", data: "download:start" },
    { label: "🌐 Open in Mini App", data: "miniapp:open" },
  ];
}

/** Build ≤50 results with next_offset semantics (T-S11-2). */
export async function buildInlineResults(query: string, offset = 0): Promise<{ results: InlineResult[]; next_offset?: string }> {
  const { term, facet } = parseInlineQuery(query);
  if (!term) return { results: [] };
  const all = await rankCatalogue(term, facet ?? "all");
  const page = all.slice(offset, offset + INLINE_PAGE_SIZE);
  const results: InlineResult[] = page.map((t) => ({
    id: t.id,
    type: "audio",
    title: t.title,
    performer: t.artist,
    caption: captionFor(t.title, t.artist, t.album, t.year),
    buttons: inlineButtons(),
  }));
  const next = offset + INLINE_PAGE_SIZE;
  return next < Math.min(all.length, INLINE_MAX_RESULTS) ? { results, next_offset: String(next) } : { results };
}

export async function telegramAnswerInlineArgs(query: string, offset = 0) {
  const { results, next_offset } = await buildInlineResults(query, offset);
  return { cache_time: INLINE_CACHE_TIME_SEC, next_offset, results };
}
