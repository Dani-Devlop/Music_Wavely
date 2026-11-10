"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import { fmtTime } from "@/lib/wavely/data";
import { cachedLyrics, isRtlText, parseLrc, storeLyrics } from "@/lib/wavely/lyrics";
import type { FetchedLyrics } from "@/lib/wavely/lyrics";
import type { LyricLine } from "@/lib/wavely/types";
import { Languages, Loader2, Mic2, Music, Search, Undo2, VolumeX } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";

interface Candidate {
  trackName: string;
  artistName: string;
  duration: number | null;
  instrumental: boolean;
  synced: string | null;
  plain: string | null;
}

type Resolved =
  | { kind: "synced"; lines: LyricLine[]; via: string }
  | { kind: "plain"; lines: string[]; via: string }
  | { kind: "instrumental-remote" }
  | { kind: "not-found" };

function resolveFrom(fl: FetchedLyrics | null): Resolved {
  if (!fl) return { kind: "not-found" };
  if (fl.synced && fl.synced.length > 0) return { kind: "synced", lines: fl.synced, via: fl.source };
  if (fl.plain && fl.plain.length > 0) return { kind: "plain", lines: fl.plain, via: fl.source };
  return { kind: "not-found" };
}

/** translations per track — session-scoped, like the lyrics cache itself */
const translationCache = new Map<string, string[]>();

/**
 * Lyrics experience (user-confirmed rules):
 *  - embedded synced tags first, otherwise auto-fetch from LRCLIB on open
 *  - synced when available; plain text still gets shown (never hidden)
 *  - nothing found → manual search till it turns up; "instrumental" stops retrying
 *  - very strict auto matching (a wrong lyric is worse than no lyric)
 *  - Persian lyrics render RTL inside the lyrics area only
 *  - optional line-aligned translation into the user's language
 */
export function LyricsPanel() {
  const track = useCurrentTrack();
  const position = useWavely((s) => s.position);
  const seek = useWavely((s) => s.seek);
  const instrumentalIds = useWavely((s) => s.instrumentalIds);
  const toggleInstrumental = useWavely((s) => s.toggleInstrumental);
  const containerRef = useRef<HTMLDivElement>(null);
  const { toast } = useToast();

  const trackId = track?.id;
  const embedded = track?.lyrics ?? [];
  const isInstrumental = !!trackId && instrumentalIds.includes(trackId);

  const [resolved, setResolved] = useState<Resolved | null>(null);
  const [candidates, setCandidates] = useState<Candidate[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [query, setQuery] = useState("");

  const [translateOn, setTranslateOn] = useState(false);
  const [translated, setTranslated] = useState<string[] | null>(null);
  const [translating, setTranslating] = useState(false);

  /* reset the whole flow when the track changes */
  useEffect(() => {
    setResolved(null);
    setCandidates(null);
    setQuery("");
    setTranslated(null);
    setTranslateOn(false);
  }, [trackId]);

  /* rule 1 (my proposal, accepted): auto-fetch when the lyrics view opens —
     but never for instrumental-marked tracks, and never twice per session */
  useEffect(() => {
    if (!trackId) return;
    const t = useWavely.getState().currentTrack();
    if (!t || t.lyrics?.length) return;
    if (useWavely.getState().instrumentalIds.includes(t.id)) return;
    const hit = cachedLyrics(t.id);
    if (hit !== undefined) {
      setResolved(resolveFrom(hit));
      setQuery(`${t.artist} ${t.title}`);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(
          `/api/lyrics?artist=${encodeURIComponent(t.artist)}&title=${encodeURIComponent(t.title)}` +
            `&album=${encodeURIComponent(t.album)}&duration=${Math.round(t.duration)}`,
        );
        const data = await res.json();
        if (cancelled) return;
        if (data.ok && data.instrumental) {
          storeLyrics(t.id, null);
          setResolved({ kind: "instrumental-remote" });
        } else if (data.ok && (data.synced || data.plain)) {
          const fl: FetchedLyrics = {
            synced: data.synced ? parseLrc(data.synced) : undefined,
            plain: data.plain
              ? String(data.plain).split("\n").filter((l: string) => l.trim().length > 0)
              : undefined,
            source: "LRCLIB",
          };
          storeLyrics(t.id, fl.synced || fl.plain ? fl : null);
          setResolved(resolveFrom(fl));
        } else {
          storeLyrics(t.id, null);
          setResolved({ kind: "not-found" });
        }
      } catch {
        if (!cancelled) setResolved({ kind: "not-found" });
      }
      if (!cancelled) setQuery(`${t.artist} ${t.title}`);
    })();
    return () => {
      cancelled = true;
    };
  }, [trackId]);

  const effective: Resolved | null =
    embedded.length > 0 ? { kind: "synced", lines: embedded, via: "embedded tags" } : resolved;

  const syncedLines = effective?.kind === "synced" ? effective.lines : null;

  const activeIndex = useMemo(() => {
    if (!syncedLines) return -1;
    let idx = -1;
    for (let i = 0; i < syncedLines.length; i++) {
      if (syncedLines[i].time <= position) idx = i;
      else break;
    }
    return idx;
  }, [syncedLines, position]);

  // auto-scroll active line into view
  useEffect(() => {
    const el = containerRef.current?.querySelector<HTMLElement>(`[data-line="${activeIndex}"]`);
    el?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, [activeIndex]);

  const currentLines: string[] =
    effective?.kind === "synced"
      ? effective.lines.map((l) => l.text)
      : effective?.kind === "plain"
        ? effective.lines
        : [];
  const rtlOriginal = isRtlText(currentLines);
  const rtlTranslated = translated ? isRtlText(translated) : false;

  /* ---------- actions ---------- */

  const runSearch = async () => {
    const q = query.trim();
    if (!q || searching) return;
    setSearching(true);
    try {
      const res = await fetch(`/api/lyrics?q=${encodeURIComponent(q)}`);
      const data = await res.json();
      setCandidates(data.ok ? (data.candidates as Candidate[]) : []);
      if (!data.ok || !data.candidates?.length) {
        toast({ description: "Nothing on LRCLIB for that query — try another spelling" });
      }
    } catch {
      toast({ description: "Search failed — check your connection" });
    } finally {
      setSearching(false);
    }
  };

  const applyCandidate = (c: Candidate) => {
    if (!trackId) return;
    const fl: FetchedLyrics = {
      synced: c.synced ? parseLrc(c.synced) : undefined,
      plain: c.plain ? c.plain.split("\n").filter((l) => l.trim().length > 0) : undefined,
      source: "LRCLIB",
    };
    storeLyrics(trackId, fl.synced || fl.plain ? fl : null);
    setResolved(resolveFrom(fl.synced || fl.plain ? fl : null));
    setCandidates(null);
    if (fl.synced || fl.plain) {
      toast({ description: `Lyrics applied — ${c.trackName} · ${c.artistName}` });
    } else {
      toast({ description: "That version has no text — try another candidate" });
    }
  };

  const doTranslate = async () => {
    if (!trackId || currentLines.length === 0) return;
    if (translateOn) {
      setTranslateOn(false);
      return;
    }
    setTranslateOn(true);
    const cached = translationCache.get(trackId);
    if (cached) {
      setTranslated(cached);
      return;
    }
    setTranslating(true);
    try {
      const res = await fetch("/api/translate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ lines: currentLines, target: "Persian (Farsi)" }),
      });
      const data = await res.json();
      if (!data.ok) throw new Error("failed");
      translationCache.set(trackId, data.lines as string[]);
      setTranslated(data.lines as string[]);
      toast({ description: "Translated to فارسی" });
    } catch {
      toast({ description: "Translation failed — try again in a moment" });
      setTranslateOn(false);
    } finally {
      setTranslating(false);
    }
  };

  /* ---------- render ---------- */

  if (!track) return null;

  /* lyrics visible → scrollable view with sticky translate chip */
  if (effective && (effective.kind === "synced" || effective.kind === "plain")) {
    const plain = effective.kind === "plain";
    return (
      <div
        ref={containerRef}
        className="wavely-scroll h-full min-h-0 overflow-y-auto overscroll-contain scroll-smooth px-5 py-3 md:px-8"
      >
        <div className="sticky top-0 z-20 flex justify-center pb-2">
          <button
            onClick={doTranslate}
            className={cn(
              "glass flex items-center gap-1.5 rounded-full px-3 py-1 text-[11px] font-semibold transition",
              translateOn ? "text-primary" : "text-muted-foreground hover:text-foreground",
            )}
            aria-pressed={translateOn}
          >
            {translating ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
            ) : (
              <Languages className="h-3.5 w-3.5" />
            )}
            {translating ? "Translating…" : translateOn ? "Hide translation" : "Translate → fa"}
          </button>
        </div>

        <div dir={rtlOriginal ? "rtl" : "ltr"} className="mx-auto max-w-xl space-y-3 md:space-y-4">
          {syncedLines?.map((line, i) => (
            <button
              key={i}
              data-line={i}
              onClick={() => seek(line.time)}
              className={cn(
                "block w-full break-words text-left font-display font-bold leading-snug transition-all duration-300",
                rtlOriginal && "text-right",
                i === activeIndex
                  ? "text-xl text-primary md:text-3xl"
                  : i < activeIndex
                    ? "text-base text-foreground/45 md:text-xl"
                    : "text-base text-foreground/28 md:text-xl",
              )}
              aria-current={i === activeIndex ? "true" : undefined}
            >
              {line.text}
              {translateOn && translated?.[i] && (
                <span
                  dir={rtlTranslated ? "rtl" : "ltr"}
                  className={cn(
                    "mt-0.5 block text-sm font-medium leading-relaxed opacity-65 md:text-base",
                    rtlTranslated ? "text-right" : "text-left",
                  )}
                >
                  {translated[i]}
                </span>
              )}
            </button>
          ))}
          {plain &&
            effective.lines.map((text, i) => (
              <div key={i} className={cn(rtlOriginal ? "text-right" : "text-left")}>
                <p className="break-words font-display text-base font-semibold leading-relaxed text-foreground/75 md:text-lg">
                  {text}
                </p>
                {translateOn && translated?.[i] && (
                  <p
                    dir={rtlTranslated ? "rtl" : "ltr"}
                    className={cn(
                      "mt-0.5 break-words text-sm leading-relaxed opacity-60 md:text-base",
                      rtlTranslated ? "text-right" : "text-left",
                    )}
                  >
                    {translated[i]}
                  </p>
                )}
              </div>
            ))}
        </div>

        <p className="pb-2 pt-4 text-center text-xs text-muted-foreground">
          {plain
            ? `Plain text via ${effective.via} — no timestamps available`
            : `Tap a line to jump • synced via ${effective.via}`}
        </p>
      </div>
    );
  }

  /* centered states: loading / not found / instrumental */
  const center = "flex h-full flex-col items-center justify-center gap-4 p-8 text-center";

  if (isInstrumental) {
    return (
      <div className={center}>
        <div className="flex h-16 w-16 items-center justify-center rounded-full bg-accent">
          <VolumeX className="h-7 w-7 text-muted-foreground" />
        </div>
        <div>
          <p className="font-medium">Marked as instrumental</p>
          <p className="mt-1 max-w-xs text-sm text-muted-foreground">
            Wavely won&apos;t look for lyrics on this track anymore.
          </p>
        </div>
        <Button
          variant="outline"
          className="gap-2 rounded-full"
          onClick={() => {
            toggleInstrumental(track.id);
            toast({ description: "Will search lyrics again for this track" });
          }}
        >
          <Undo2 className="h-4 w-4" /> Undo
        </Button>
      </div>
    );
  }

  if (!effective || effective.kind === "instrumental-remote") {
    return (
      <div className={center}>
        <div className="flex h-16 w-16 items-center justify-center rounded-full bg-accent">
          {effective?.kind === "instrumental-remote" ? (
            <Music className="h-7 w-7 text-muted-foreground" />
          ) : (
            <Loader2 className="h-7 w-7 animate-spin text-muted-foreground" />
          )}
        </div>
        {effective?.kind === "instrumental-remote" ? (
          <>
            <div>
              <p className="font-medium">LRCLIB says this track is instrumental</p>
              <p className="mt-1 max-w-xs text-sm text-muted-foreground">
                No vocals to show — mark it so Wavely stops searching.
              </p>
            </div>
            <Button
              variant="outline"
              className="gap-2 rounded-full"
              onClick={() => {
                toggleInstrumental(track.id);
                toast({ description: "Marked as instrumental — no more lyrics searches" });
              }}
            >
              <VolumeX className="h-4 w-4" /> Mark as instrumental
            </Button>
          </>
        ) : (
          <p className="text-sm text-muted-foreground">Searching LRCLIB…</p>
        )}
      </div>
    );
  }

  /* not found → manual search till it turns up (user rule 3) */
  return (
    <div className={cn(center, "justify-start pt-10")}>
      <div className="flex h-14 w-14 items-center justify-center rounded-full bg-accent">
        <Mic2 className="h-6 w-6 text-muted-foreground" />
      </div>
      <div>
        <p className="font-medium">No lyrics found</p>
        <p className="mt-1 max-w-xs text-sm text-muted-foreground">
          Wavely checks embedded tags first, then .lrc files, then LRCLIB. Search manually to dig
          it up.
        </p>
      </div>

      <form
        className="flex w-full max-w-xs items-center gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          runSearch();
        }}
      >
        <Input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Artist — Title"
          aria-label="Search lyrics"
          className="h-9 flex-1 rounded-full bg-accent/50 text-sm"
        />
        <Button
          type="submit"
          size="icon"
          className="h-9 w-9 shrink-0 rounded-full"
          disabled={searching || !query.trim()}
          aria-label="Search"
        >
          {searching ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
        </Button>
      </form>

      {candidates && candidates.length > 0 && (
        <div className="wavely-scroll max-h-56 w-full max-w-xs space-y-1 overflow-y-auto rounded-xl bg-accent/25 p-1.5">
          {candidates.map((c, i) => (
            <button
              key={`${c.trackName}-${c.artistName}-${i}`}
              onClick={() => applyCandidate(c)}
              className="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left transition hover:bg-accent/70"
            >
              <Music className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[13px] font-semibold">{c.trackName}</span>
                <span className="block truncate text-[11px] text-muted-foreground">
                  {c.artistName}
                  {c.duration ? ` · ${fmtTime(c.duration)}` : ""}
                </span>
              </span>
              <span className="shrink-0 rounded-full bg-primary/15 px-1.5 py-0.5 text-[9px] font-bold text-primary">
                {c.instrumental ? "inst." : c.synced ? "synced" : "plain"}
              </span>
            </button>
          ))}
        </div>
      )}

      <Button
        variant="ghost"
        className="gap-2 rounded-full text-muted-foreground"
        onClick={() => {
          toggleInstrumental(track.id);
          toast({ description: "Marked as instrumental — no more lyrics searches" });
        }}
      >
        <VolumeX className="h-4 w-4" /> It&apos;s instrumental — stop searching
      </Button>
    </div>
  );
}
