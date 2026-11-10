import type { LyricLine } from "./types";

/** A lyrics result resolved from the pipeline (embedded → .lrc → LRCLIB). */
export interface FetchedLyrics {
  /** synced lines (LRC parsed) when LRCLIB had timestamps */
  synced?: LyricLine[];
  /** plain text lines as the graceful fallback — shown without sync */
  plain?: string[];
  source: string;
}

/**
 * Session lyrics cache — the prototype stand-in for the app's Drift
 * `lyrics_cache` table. `null` = searched and not found, kept so the app
 * never re-queries on every open (no TTL: cache is size-managed, not
 * time-managed — user rule: live inside the 350–400 MB cache budget).
 */
const cache = new Map<string, FetchedLyrics | null>();

export function cachedLyrics(trackId: string): FetchedLyrics | null | undefined {
  return cache.get(trackId);
}

export function storeLyrics(trackId: string, lyrics: FetchedLyrics | null): void {
  cache.set(trackId, lyrics);
}

/** Parse an LRC string ("[mm:ss.xx] line", multiple stamps per line allowed). */
export function parseLrc(lrc: string): LyricLine[] {
  const lines: LyricLine[] = [];
  for (const raw of lrc.split("\n")) {
    const stamps = [...raw.matchAll(/\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g)];
    if (stamps.length === 0) continue;
    const text = raw.replace(/\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g, "").trim();
    for (const m of stamps) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      const frac = m[3] ? parseFloat(`0.${m[3]}`) : 0;
      lines.push({ time: +(min * 60 + sec + frac).toFixed(2), text });
    }
  }
  return lines.sort((a, b) => a.time - b.time);
}

const RTL_RE = /[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]/g;

/** True when the text is written in an RTL script (Persian/Arabic/…). */
export function isRtlText(texts: string[]): boolean {
  const sample = texts.filter(Boolean).join(" ");
  if (!sample) return false;
  const rtlCount = (sample.match(RTL_RE) ?? []).length;
  return rtlCount > sample.length * 0.15;
}
