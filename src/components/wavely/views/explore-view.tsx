"use client";

import { useMemo, useState } from "react";
import { SongRow } from "../song-row";
import { CuratedCard, ReleaseCard } from "../cards";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import { CACHE_LIMIT_MB, useCacheUsage } from "@/lib/wavely/store";
import {
  ALBUMS,
  FOLLOWED_ARTIST_IDS,
  TRACKS,
  fmtAge,
  trackById,
  tracksOfAlbum,
} from "@/lib/wavely/data";
import { Cloud, CloudOff, Compass, Heart, Sparkles } from "lucide-react";
import { cn } from "@/lib/utils";

type Window = "7" | "14" | "30" | "visit";

const WINDOWS: { id: Window; label: string }[] = [
  { id: "7", label: "1 week" },
  { id: "14", label: "2 weeks" },
  { id: "30", label: "1 month" },
  { id: "visit", label: "Since last visit" },
];

function SectionTitle({ children, hint }: { children: React.ReactNode; hint?: string }) {
  return (
    <div className="mb-2 flex items-baseline justify-between gap-3">
      <h2 className="font-display text-lg font-bold tracking-tight md:text-xl">{children}</h2>
      {hint && <span className="truncate text-[11px] text-muted-foreground">{hint}</span>}
    </div>
  );
}

export function ExploreView() {
  const playContext = useWavely((s) => s.playContext);
  const setView = useWavely((s) => s.setView);
  const isOffline = useWavely((s) => s.isOffline);
  const lastOnlineAt = useWavely((s) => s.lastOnlineAt);
  const cachedIds = useWavely((s) => s.cachedIds);
  const currentTrack = useCurrentTrack();
  const cacheUsed = useCacheUsage();
  const [win, setWin] = useState<Window>("30");

  const onlineAlbums = useMemo(() => ALBUMS.filter((a) => a.origin === "online"), []);

  const inWindow = (releasedAt: number) => {
    if (win === "visit") return releasedAt > lastOnlineAt;
    return Date.now() - releasedAt <= Number(win) * 86400000;
  };

  const followedReleases = useMemo(
    () =>
      onlineAlbums
        .filter((a) => a.releasedAt && inWindow(a.releasedAt) && FOLLOWED_ARTIST_IDS.includes(a.artistId))
        .sort((a, b) => (b.releasedAt ?? 0) - (a.releasedAt ?? 0)),
    [win, lastOnlineAt, onlineAlbums],
  );

  const moreReleases = useMemo(
    () =>
      onlineAlbums
        .filter((a) => a.releasedAt && inWindow(a.releasedAt) && !FOLLOWED_ARTIST_IDS.includes(a.artistId))
        .sort((a, b) => (b.releasedAt ?? 0) - (a.releasedAt ?? 0)),
    [win, lastOnlineAt, onlineAlbums],
  );

  const topStreams = useMemo(
    () => TRACKS.filter((t) => t.origin === "online" && !t.downloaded).sort((a, b) => b.playCount - a.playCount).slice(0, 8),
    [],
  );

  const cachedTracks = useMemo(
    () => cachedIds.map((id) => trackById.get(id)!).filter(Boolean),
    [cachedIds],
  );

  const discoverMix = ["t35", "t39", "t43", "t36", "t40", "t44", "t38", "t41"];

  const playAlbum = (albumId: string, title: string) =>
    playContext(title, tracksOfAlbum(albumId).map((t) => t.id), 0);

  return (
    <div className="mx-auto w-full max-w-md space-y-7 px-4 pb-10 pt-4 md:max-w-3xl md:px-8 md:pt-6 lg:max-w-5xl">
      {/* header */}
      <header className="flex items-center gap-3">
        <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-sky-400/12 text-sky-300">
          <Compass className="h-6 w-6" />
        </span>
        <div className="min-w-0 flex-1">
          <h1 className="font-display text-2xl font-bold tracking-tight">Explore</h1>
          <p className="truncate text-xs text-muted-foreground">
            Streaming world — new drops, picks &amp; charts
          </p>
        </div>
        {!isOffline && (
          <span
            className="shrink-0 rounded-full bg-secondary px-3 py-1.5 text-[11px] font-semibold text-muted-foreground"
            title="Streaming cache — invisible app storage, auto-evicted (LRU) at 400 MB"
          >
            Cache {cacheUsed} / {CACHE_LIMIT_MB} MB
          </span>
        )}
      </header>

      {isOffline ? (
        /* ---------------- offline: cached songs remain ---------------- */
        <section className="space-y-2">
          <div className="flex items-center gap-2.5 rounded-xl bg-amber-500/10 px-3.5 py-2.5 text-[13px] text-amber-300/90">
            <CloudOff className="h-4 w-4 shrink-0" />
            <p>
              You&apos;re offline — the streaming catalogue is hidden. Songs cached from earlier
              sessions still play below, and can be saved instantly while offline.
            </p>
          </div>
          {cachedTracks.length > 0 ? (
            <div className="rounded-2xl bg-wav-surface/50 p-1.5">
              <p className="px-2 pb-1 pt-2 text-[10px] font-bold uppercase tracking-widest text-emerald-300">
                Cached from streaming — {cachedTracks.length} song{cachedTracks.length > 1 ? "s" : ""}
              </p>
              {cachedTracks.map((t, i) => (
                <SongRow
                  key={t.id}
                  track={t}
                  index={i}
                  compact
                  onPlay={() => playContext("Cached songs", cachedIds, i)}
                />
              ))}
            </div>
          ) : (
            <p className="rounded-xl border border-dashed border-border px-4 py-6 text-center text-sm text-muted-foreground">
              Nothing cached yet — play a few online songs while connected first.
            </p>
          )}
        </section>
      ) : (
        <>
          {/* ---------------- new releases — time windows ---------------- */}
          <section>
            <SectionTitle hint="from artists you follow">New releases</SectionTitle>
            <div className="no-scrollbar -mx-4 mb-3 flex gap-2 overflow-x-auto px-4 md:mx-0 md:px-0">
              {WINDOWS.map((w) => (
                <button
                  key={w.id}
                  onClick={() => setWin(w.id)}
                  className={cn(
                    "flex h-8 shrink-0 items-center gap-1.5 rounded-full px-3.5 text-xs font-semibold transition-all",
                    win === w.id
                      ? "bg-primary text-primary-foreground shadow-md shadow-primary/25"
                      : "border border-border bg-secondary/80 text-muted-foreground hover:text-foreground",
                  )}
                  aria-pressed={win === w.id}
                >
                  {w.id === "visit" && <Sparkles className="h-3 w-3" />}
                  {w.label}
                </button>
              ))}
            </div>

            {followedReleases.length > 0 ? (
              <div className="no-scrollbar -mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
                {followedReleases.map((a) => (
                  <ReleaseCard
                    key={a.id}
                    cover={a.cover}
                    title={a.title}
                    meta={`${a.artist} • ${fmtAge(a.releasedAt!)}`}
                    playing={currentTrack !== undefined && tracksOfAlbum(a.id).some((t) => t.id === currentTrack.id)}
                    onPlay={() => playAlbum(a.id, a.title)}
                  />
                ))}
              </div>
            ) : (
              <p className="rounded-xl border border-dashed border-border px-4 py-5 text-center text-sm text-muted-foreground">
                Nothing new in this window — widen it, or check back soon.
              </p>
            )}

            {moreReleases.length > 0 && (
              <>
                <p className="mb-2 mt-4 text-sm font-bold text-muted-foreground">
                  More new music
                </p>
                <div className="no-scrollbar -mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
                  {moreReleases.map((a) => (
                    <ReleaseCard
                      key={a.id}
                      cover={a.cover}
                      title={a.title}
                      meta={`${a.artist} • ${fmtAge(a.releasedAt!)}`}
                      playing={currentTrack !== undefined && tracksOfAlbum(a.id).some((t) => t.id === currentTrack.id)}
                      onPlay={() => playAlbum(a.id, a.title)}
                    />
                  ))}
                </div>
              </>
            )}
          </section>

          {/* ---------------- made for you ---------------- */}
          <section>
            <SectionTitle>Made for you</SectionTitle>
            <div className="no-scrollbar -mx-4 flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
              <CuratedCard
                image="/wavely/curated-1.png"
                badge="ai"
                title="Wavely Weekly"
                subtitle="Fresh picks built from what you play — updated every Monday."
                onPlay={() => playContext("Wavely Weekly", discoverMix, 0)}
              />
              <CuratedCard
                badge="ai"
                title="Wavely AI DJ"
                subtitle="Ask for a playlist, song facts, or just say “surprise me”."
                onPlay={() => setView("ai")}
              />
              <CuratedCard
                image="/covers/online-chrome-city.png"
                badge="online"
                title="Chrome City — full album stream"
                subtitle="Midnight Arcade's new synthpop LP, streaming in 320kbps."
                onPlay={() => playAlbum("al9", "Chrome City")}
              />
            </div>
          </section>

          {/* ---------------- charts ---------------- */}
          <section>
            <SectionTitle hint="most played across Wavely">Top streaming now</SectionTitle>
            <div className="rounded-2xl bg-wav-surface/50 p-1.5">
              {topStreams.map((t, i) => (
                <SongRow
                  key={t.id}
                  track={t}
                  index={i}
                  onPlay={() => playContext("Top streaming now", topStreams.map((x) => x.id), i)}
                />
              ))}
            </div>
          </section>

          {/* liked hint — likes live across both worlds */}
          <p className="flex items-center justify-center gap-1.5 pb-2 text-center text-xs text-muted-foreground">
            <Heart className="h-3.5 w-3.5 fill-primary text-primary" />
            Like anything here and it lands in your Liked songs on Home — online badge included.
            <Cloud className="h-3.5 w-3.5 text-sky-300" />
          </p>
        </>
      )}
    </div>
  );
}
