import { NextRequest, NextResponse } from "next/server";

/**
 * Lyrics proxy → LRCLIB (same source as the real app's LrclibLyricsProvider).
 *
 * Two modes:
 *  - auto:   /api/lyrics?artist=&title=&album=&duration= → /api/get exact,
 *            then /api/search with a VERY strict match gate (user rule 7:
 *            a wrong lyric is worse than no lyric).
 *  - search: /api/lyrics?q=…                             → raw candidate list,
 *            the user picks the right one themselves (user rule 3).
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const UA = "Wavely/1.0 (web prototype; +https://github.com/Dani-Devlop/Music_Wavely)";
const TIMEOUT_MS = 10_000;

interface LrcLibHit {
  id: number;
  trackName: string;
  artistName: string;
  albumName?: string | null;
  duration?: number | null;
  instrumental?: boolean;
  plainLyrics?: string | null;
  syncedLyrics?: string | null;
}

/** Strip download-site spam so noisy Persian/YouTube tags don't poison the match. */
function cleanText(s: string): string {
  return s
    .toLowerCase()
    .replace(/\((?:official|lyrics?|audio|video|hd|4k|hq)[^)]*\)/g, " ")
    .replace(/\[[^\]]*\]/g, " ")
    .replace(/\b\d{3}\s*kbps\b|\bmp3\b|\bflac\b|\b320\b/g, " ")
    .replace(/@\w+|https?:\/\/\S+|t\.me\/\S+/g, " ")
    .replace(/دانلود آهنگ|دانلود اهنگ|پخش آنلاین|پخش انلاین|کیفیت اصلی/g, " ")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function tokens(s: string): Set<string> {
  return new Set(cleanText(s).split(" ").filter(Boolean));
}

/** Word-overlap containment — how much of the smaller token set is covered. */
function overlap(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let hit = 0;
  for (const t of a) if (b.has(t)) hit++;
  return hit / Math.min(a.size, b.size);
}

/* Strictness gates — deliberately high (user: "سخت گیری مچ خیلی بالا باشه") */
const MIN_TITLE = 0.8;
const MIN_ARTIST = 0.65;
const MAX_DURATION_DRIFT = 4; // seconds

async function lrclib(path: string): Promise<LrcLibHit | LrcLibHit[] | null> {
  try {
    const res = await fetch(`https://lrclib.net${path}`, {
      headers: { "User-Agent": UA },
      signal: AbortSignal.timeout(TIMEOUT_MS),
      cache: "no-store",
    });
    if (!res.ok) return null;
    return (await res.json()) as LrcLibHit | LrcLibHit[];
  } catch {
    return null;
  }
}

function shape(hit: LrcLibHit) {
  return {
    trackName: hit.trackName,
    artistName: hit.artistName,
    duration: hit.duration ?? null,
    instrumental: !!hit.instrumental,
    synced: hit.syncedLyrics ?? null,
    plain: hit.plainLyrics ?? null,
  };
}

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const q = sp.get("q")?.trim();

  /* manual search — hand back candidates, the user decides */
  if (q) {
    const hits = await lrclib(`/api/search?q=${encodeURIComponent(q)}`);
    const candidates = (Array.isArray(hits) ? hits : []).slice(0, 6).map(shape);
    return NextResponse.json({ ok: true, mode: "search", candidates });
  }

  const artist = sp.get("artist")?.trim() ?? "";
  const title = sp.get("title")?.trim() ?? "";
  const album = sp.get("album")?.trim() || "";
  const durationRaw = Number(sp.get("duration"));
  const duration = isFinite(durationRaw) && durationRaw > 0 ? durationRaw : undefined;
  if (!artist || !title) {
    return NextResponse.json({ ok: false, reason: "missing_params" }, { status: 400 });
  }

  /* 1) exact lookup first */
  const params = new URLSearchParams({ artist_name: artist, track_name: title });
  if (album) params.set("album_name", album);
  if (duration) params.set("duration", String(Math.round(duration)));
  const exact = await lrclib(`/api/get?${params.toString()}`);
  if (exact && !Array.isArray(exact) && (exact.syncedLyrics || exact.plainLyrics || exact.instrumental)) {
    return NextResponse.json({ ok: true, mode: "auto", ...shape(exact) });
  }

  /* 2) strict-scored search fallback — reject weak matches outright */
  const hits = await lrclib(
    `/api/search?track_name=${encodeURIComponent(title)}&artist_name=${encodeURIComponent(artist)}`,
  );
  if (Array.isArray(hits)) {
    const best = hits
      .map((h) => {
        const t = overlap(tokens(title), tokens(h.trackName));
        const a = overlap(tokens(artist), tokens(h.artistName));
        const dOk =
          !duration || !h.duration ? true : Math.abs(duration - h.duration) <= MAX_DURATION_DRIFT;
        return { h, t, a, dOk };
      })
      .filter((x) => x.dOk && x.t >= MIN_TITLE && x.a >= MIN_ARTIST)
      .sort((x, y) => y.t + y.a - (x.t + x.a))[0];
    if (best && (best.h.syncedLyrics || best.h.plainLyrics || best.h.instrumental)) {
      return NextResponse.json({ ok: true, mode: "auto", ...shape(best.h) });
    }
  }

  return NextResponse.json({ ok: false, reason: "not_found" });
}
