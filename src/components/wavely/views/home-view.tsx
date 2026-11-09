"use client";

import Image from "next/image";
import { useMemo } from "react";
import { motion } from "framer-motion";
import { SongRow } from "../song-row";
import { CuratedCard, ReleaseCard } from "../cards";
import { OfflineBanner } from "../source-mode-chips";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import {
  ALBUMS,
  PLAYLISTS,
  TRACKS,
  fmtAge,
  fmtLongTime,
  trackById,
} from "@/lib/wavely/data";
import type { LibraryTab, SongFilter, SongSortMode } from "@/lib/wavely/types";
import { Button } from "@/components/ui/button";
import {
  ArrowRight,
  Ban,
  ChevronRight,
  ClockPlus,
  CloudOff,
  Compass,
  Disc3,
  Flame,
  Heart,
  History,
  LibraryBig,
  ListMusic,
  ListPlus,
  MicVocal,
  Play,
  Smartphone,
  Sparkles,
} from "lucide-react";
import { cn } from "@/lib/utils";

function greeting(): string {
  const h = new Date().getHours();
  if (h < 5) return "Good night";
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  if (h < 22) return "Good evening";
  return "Good night";
}

function SectionHeader({ title, action }: { title: string; action?: React.ReactNode }) {
  return (
    <div className="mb-3 flex items-center justify-between">
      <h2 className="font-display text-lg font-bold tracking-tight md:text-xl">{title}</h2>
      {action}
    </div>
  );
}

/** Jumps into My Music with a specific tab / sort / filter pre-applied. */
function openMyMusic(opts: { tab: LibraryTab; sort?: SongSortMode; filter?: SongFilter }) {
  const s = useWavely.getState();
  s.setLibraryTab(opts.tab);
  if (opts.sort) s.setSongSort(opts.sort);
  s.setSongFilter(opts.filter ?? "all");
  s.setView("library");
}

/* ---------------------------------------------------------------- */
/* Compact header — avatar + greeting + search, one row, no waste    */
/* ---------------------------------------------------------------- */
function HomeHeader() {
  const setView = useWavely((s) => s.setView);
  return (
    <header className="sticky top-0 z-20 -mx-4 bg-background/85 px-4 pb-2.5 pt-[max(0.5rem,env(safe-area-inset-top))] backdrop-blur-xl md:-mx-8 md:px-8">
      <div className="flex items-center gap-3">
        <button
          onClick={() => setView("settings")}
          className="relative h-10 w-10 shrink-0 overflow-hidden rounded-full ring-2 ring-primary/40 transition hover:ring-primary"
          aria-label="Open profile"
        >
          <Image src="/wavely/avatar.png" alt="Your profile" fill sizes="40px" className="object-cover" />
        </button>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[10px] font-semibold uppercase tracking-[0.2em] text-muted-foreground">
            {greeting()}
          </p>
          <h1 className="truncate font-display text-xl font-extrabold leading-tight tracking-tight">
            Hi, Dani
          </h1>
        </div>
        <button
          onClick={() => setView("search")}
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-wav-elevated text-foreground transition hover:bg-accent"
          aria-label="Search"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" className="h-5 w-5" aria-hidden="true">
            <circle cx="11" cy="11" r="7" />
            <path d="m20 20-3.5-3.5" strokeLinecap="round" />
          </svg>
        </button>
      </div>
    </header>
  );
}

/* ---------------------------------------------------------------- */
/* Liked & favorites — one combined home for both worlds             */
/* online rows keep their ☁ badge; liking happens via the ⋯ sheet.   */
/* ---------------------------------------------------------------- */
function LikedSection({
  favIds,
  onOpen,
}: {
  favIds: string[];
  onOpen: () => void;
}) {
  const playContext = useWavely((s) => s.playContext);
  const toggleShuffle = useWavely((s) => s.toggleShuffle);

  const shuffleLiked = () => {
    if (favIds.length === 0) return;
    playContext("Liked songs", favIds, Math.floor(Math.random() * favIds.length));
    if (!useWavely.getState().shuffle) toggleShuffle();
  };

  return (
    <section>
      <SectionHeader
        title="Liked & favorites"
        action={
          <Button variant="ghost" size="sm" className="text-xs text-muted-foreground" onClick={onOpen}>
            See all
          </Button>
        }
      />
      <div className="grid gap-2 sm:grid-cols-2">
        <motion.button
          whileTap={{ scale: 0.985 }}
          onClick={onOpen}
          className="group relative flex min-h-40 flex-col justify-between overflow-hidden rounded-2xl bg-gradient-to-br from-primary/45 via-primary/18 to-transparent p-4 text-left"
          aria-label="Open liked songs"
        >
          <span className="flex h-11 w-11 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg accent-glow">
            <Heart className="h-5 w-5 fill-primary-foreground" />
          </span>
          <span className="mt-4 block">
            <span className="block font-display text-lg font-bold">Liked songs</span>
            <span className="mt-0.5 block text-xs text-muted-foreground">
              {favIds.length} songs — whatever you love, in one place
            </span>
          </span>
          <span
            role="button"
            tabIndex={0}
            onClick={(e) => {
              e.stopPropagation();
              shuffleLiked();
            }}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.stopPropagation();
                shuffleLiked();
              }
            }}
            className="absolute bottom-4 right-4 flex h-11 w-11 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-xl transition-all hover:scale-105 focus-visible:opacity-100 group-hover:opacity-100"
            aria-label="Shuffle liked songs"
          >
            <Play className="ml-0.5 h-5 w-5 fill-primary-foreground" />
          </span>
        </motion.button>

        <div className="flex flex-col justify-center rounded-2xl bg-wav-surface/60 p-1.5">
          {favIds.slice(0, 3).map((id) => {
            const t = trackById.get(id)!;
            return (
              <SongRow
                key={id}
                track={t}
                compact
                onPlay={() => playContext("Liked songs", favIds, favIds.indexOf(id))}
              />
            );
          })}
          {favIds.length > 3 && (
            <button
              onClick={onOpen}
              className="flex items-center gap-1.5 px-2 pb-1.5 pt-1 text-xs font-semibold text-muted-foreground transition hover:text-primary"
            >
              +{favIds.length - 3} more <ChevronRight className="h-3 w-3" />
            </button>
          )}
        </div>
      </div>
    </section>
  );
}

/* ---------------------------------------------------------------- */
/* LOCAL world — Musicolet-style flat rows ("My Music")              */
/* Folder browsing lives inside My Music → Folders, not on Home.     */
/* ---------------------------------------------------------------- */
function MusicoletRow({
  icon: Icon,
  label,
  detail,
  onClick,
  active,
}: {
  icon: React.ElementType;
  label: string;
  detail?: string;
  onClick: () => void;
  active?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-4 rounded-xl px-2.5 py-2 text-left transition hover:bg-accent/60",
        active && "bg-accent/40",
      )}
    >
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/12 text-primary">
        <Icon className="h-5 w-5" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[15px] font-semibold leading-tight">{label}</span>
        {detail && <span className="block truncate text-xs text-muted-foreground">{detail}</span>}
      </span>
      <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground/50" />
    </button>
  );
}

function QuickLink({
  icon: Icon,
  label,
  count,
  onClick,
}: {
  icon: React.ElementType;
  label: string;
  count: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="flex items-center gap-3 rounded-xl bg-wav-surface px-3 py-2.5 text-left transition hover:bg-accent"
    >
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary/12 text-primary">
        <Icon className="h-4 w-4" />
      </span>
      <span className="min-w-0">
        <span className="block truncate text-[13px] font-semibold leading-tight">{label}</span>
        <span className="block text-[11px] text-muted-foreground">{count}</span>
      </span>
    </button>
  );
}

function LocalSection({
  deviceCount,
  deviceTime,
  notPlayedCount,
}: {
  deviceCount: number;
  deviceTime: string;
  notPlayedCount: number;
}) {
  const favorites = useWavely((s) => s.favorites);
  const history = useWavely((s) => s.history);
  const queues = useWavely((s) => s.queues);
  const currentTrack = useCurrentTrack();

  const deviceFavorites = favorites.filter(onDevice).length;
  const deviceHistory = history.filter(onDevice).length;
  const deviceAlbums = ALBUMS.filter((a) => a.origin !== "online").length;
  const deviceGenres = new Set(
    TRACKS.filter((t) => t.origin === "local" || t.downloaded).map((t) => t.genre),
  ).size;
  const wavelyDownloads = TRACKS.filter((t) => t.downloaded).length;

  return (
    <section>
      <div className="mb-2 flex items-center gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/12 text-primary">
          <Smartphone className="h-5 w-5" />
        </span>
        <div className="min-w-0 flex-1">
          <h2 className="font-display text-lg font-bold tracking-tight md:text-xl">My Music</h2>
          <p className="truncate text-[11px] text-muted-foreground">
            On this device • {deviceCount} songs • {deviceTime}
            {wavelyDownloads > 0 && ` • ${wavelyDownloads} saved from online`}
          </p>
        </div>
        <Button
          variant="ghost"
          size="sm"
          className="text-xs text-muted-foreground"
          onClick={() => openMyMusic({ tab: "songs", sort: "title-asc" })}
        >
          Open
        </Button>
      </div>

      <div className="rounded-2xl bg-wav-surface/50 p-1.5">
        <MusicoletRow
          icon={LibraryBig}
          label="All songs"
          detail={`${deviceCount} songs on device`}
          onClick={() => openMyMusic({ tab: "songs", sort: "title-asc" })}
        />
        <MusicoletRow
          icon={Heart}
          label="Favorites"
          detail={`${deviceFavorites} songs`}
          onClick={() => openMyMusic({ tab: "favorites" })}
        />
        <MusicoletRow
          icon={ClockPlus}
          label="Recently added"
          detail="newest imports first"
          onClick={() => openMyMusic({ tab: "songs", sort: "date-added" })}
        />
        <MusicoletRow
          icon={History}
          label="Recently played"
          detail={`${deviceHistory} in device history`}
          onClick={() => openMyMusic({ tab: "history" })}
        />
        <MusicoletRow
          icon={Flame}
          label="Most played"
          detail="sorted by play count"
          onClick={() => openMyMusic({ tab: "songs", sort: "play-count" })}
        />
        <MusicoletRow
          icon={Ban}
          label="Not played"
          detail={`${notPlayedCount} songs waiting for you`}
          onClick={() => openMyMusic({ tab: "songs", filter: "not-played" })}
        />
      </div>

      <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
        <QuickLink icon={Disc3} label="Albums" count={`${deviceAlbums}`} onClick={() => openMyMusic({ tab: "albums" })} />
        <QuickLink icon={MicVocal} label="Artists" count="8 on device" onClick={() => openMyMusic({ tab: "artists" })} />
        <QuickLink icon={ListPlus} label="Playlists" count={`${PLAYLISTS.length}`} onClick={() => openMyMusic({ tab: "playlists" })} />
        <QuickLink icon={ListMusic} label="Queues" count={`${queues.length}/20`} onClick={() => openMyMusic({ tab: "queues" })} />
        <QuickLink
          icon={currentTrack ? ListMusic : Sparkles}
          label={currentTrack ? "Now playing queue" : "Ask Wavely AI"}
          count={currentTrack ? "open the queue sheet" : "build a playlist by chat"}
          onClick={() =>
            currentTrack
              ? useWavely.getState().setQueueSheetOpen(true)
              : useWavely.getState().setView("ai")
          }
        />
        <QuickLink
          icon={MicVocal}
          label="Genres"
          count={`${deviceGenres} on device`}
          onClick={() => openMyMusic({ tab: "genres" })}
        />
      </div>
    </section>
  );
}

/* ---------------------------------------------------------------- */
/* ONLINE world — compact teaser; full experience lives in Explore   */
/* ---------------------------------------------------------------- */
function ExploreSection() {
  const playContext = useWavely((s) => s.playContext);
  const setView = useWavely((s) => s.setView);
  const isOffline = useWavely((s) => s.isOffline);
  const cachedIds = useWavely((s) => s.cachedIds);
  const currentTrack = useCurrentTrack();

  const onlineTracks = useMemo(() => TRACKS.filter((t) => t.origin === "online"), []);
  const topStreams = useMemo(
    () => [...onlineTracks].sort((a, b) => b.playCount - a.playCount).slice(0, 3),
    [onlineTracks],
  );
  const newReleases = useMemo(
    () =>
      ALBUMS.filter(
        (a) => a.origin === "online" && a.releasedAt && Date.now() - a.releasedAt <= 30 * 86400000,
      ).sort((a, b) => (b.releasedAt ?? 0) - (a.releasedAt ?? 0)),
    [],
  );
  const cachedTracks = useMemo(
    () => cachedIds.map((id) => trackById.get(id)!).filter(Boolean),
    [cachedIds],
  );
  const discoverMix = ["t01", "t35", "t13", "t43", "t26", "t39", "t09", "t31", "t22", "t17"];

  return (
    <section>
      <div className="mb-2 flex items-center gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-sky-400/12 text-sky-300">
          <Compass className="h-5 w-5" />
        </span>
        <div className="min-w-0 flex-1">
          <h2 className="font-display text-lg font-bold tracking-tight md:text-xl">Explore</h2>
          <p className="truncate text-[11px] text-muted-foreground">
            Streaming catalogue • up to FLAC • new drops from artists you follow
          </p>
        </div>
        {!isOffline && (
          <Button
            variant="ghost"
            size="sm"
            className="text-xs text-muted-foreground"
            onClick={() => setView("explore")}
          >
            Open
          </Button>
        )}
      </div>

      {isOffline ? (
        <div className="space-y-2">
          <div className="flex items-center gap-2.5 rounded-xl bg-amber-500/10 px-3.5 py-2.5 text-[13px] text-amber-300/90">
            <CloudOff className="h-4 w-4 shrink-0" />
            <p>
              Online discovery is hidden while you&apos;re offline. Songs cached from streaming below
              still play — and can be saved instantly.
            </p>
          </div>
          {cachedTracks.length > 0 && (
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
          )}
        </div>
      ) : (
        <div className="space-y-5">
          {/* new releases — last month, followed artists first */}
          <div>
            <div className="mb-2 flex items-baseline justify-between">
              <h3 className="text-sm font-bold text-muted-foreground">New for you</h3>
              <button
                onClick={() => setView("explore")}
                className="flex items-center gap-1 text-xs font-semibold text-primary transition hover:text-wav-accent-hover"
              >
                1 week · 2 weeks · 1 month <ChevronRight className="h-3 w-3" />
              </button>
            </div>
            <div className="no-scrollbar -mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
              {newReleases.map((a) => (
                <ReleaseCard
                  key={a.id}
                  cover={a.cover}
                  title={a.title}
                  meta={`${a.artist} • ${fmtAge(a.releasedAt!)}`}
                  playing={currentTrack?.albumId === a.id}
                  onPlay={() =>
                    playContext(
                      a.title,
                      TRACKS.filter((t) => t.albumId === a.id).map((t) => t.id),
                      0,
                    )
                  }
                />
              ))}
            </div>
          </div>

          {/* made for you */}
          <div>
            <h3 className="mb-2 text-sm font-bold text-muted-foreground">Made for you</h3>
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
            </div>
          </div>

          {/* charts */}
          <div>
            <h3 className="mb-2 text-sm font-bold text-muted-foreground">Top streaming now</h3>
            <div className="rounded-2xl bg-wav-surface/50 p-1.5">
              {topStreams.map((t, i) => (
                <SongRow
                  key={t.id}
                  track={t}
                  index={i}
                  compact
                  onPlay={() => playContext("Top streaming now", topStreams.map((x) => x.id), i)}
                />
              ))}
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

/** Is this track a real file on the device (local scan or downloaded)? */
const onDevice = (id: string) => {
  const t = trackById.get(id);
  return !!t && (t.origin === "local" || !!t.downloaded);
};

/* ---------------------------------------------------------------- */
/* Home view                                                         */
/* ---------------------------------------------------------------- */
export function HomeView() {
  const setView = useWavely((s) => s.setView);
  const isOffline = useWavely((s) => s.isOffline);

  const favIds = useWavely((s) => s.favorites);
  const deviceTracks = useMemo(() => TRACKS.filter((t) => t.origin === "local" || t.downloaded), []);
  const notPlayedCount = useMemo(() => deviceTracks.filter((t) => t.playCount === 0).length, [deviceTracks]);
  const deviceTime = useMemo(
    () => fmtLongTime(deviceTracks.reduce((a, t) => a + t.duration, 0)),
    [deviceTracks],
  );

  return (
    <div className="mx-auto w-full max-w-md space-y-6 px-4 pb-10 md:max-w-3xl md:px-8 lg:max-w-5xl">
      <HomeHeader />

      <OfflineBanner />

      {/* combined likes — local & online side by side */}
      <LikedSection
        favIds={favIds}
        onOpen={() => {
          useWavely.getState().setLibraryTab("favorites");
          useWavely.getState().setView("library");
        }}
      />

      {/* local world — Musicolet style */}
      <LocalSection
        deviceCount={deviceTracks.length}
        deviceTime={deviceTime}
        notPlayedCount={notPlayedCount}
      />

      {/* online world — Spotify style teaser */}
      <ExploreSection />

      {/* AI DJ strip (desktop) */}
      {!isOffline && (
        <button
          onClick={() => setView("ai")}
          className="group hidden w-full items-center gap-4 overflow-hidden rounded-2xl bg-gradient-to-r from-primary/25 via-primary/10 to-transparent p-5 text-left transition hover:from-primary/35 md:flex"
        >
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-primary text-primary-foreground shadow-lg accent-glow">
            <Sparkles className="h-5 w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="font-display text-base font-bold">Wavely AI DJ</h3>
            <p className="truncate text-sm text-muted-foreground">
              Your assistant lives in the navbar — playlists, trivia, discoveries.
            </p>
          </div>
          <ArrowRight className="h-5 w-5 shrink-0 text-primary transition-transform group-hover:translate-x-1" />
        </button>
      )}

      <footer className="flex flex-wrap items-center justify-center gap-x-2 gap-y-1 pb-2 pt-2 text-center text-xs text-muted-foreground">
        Wavely prototype • Musicolet UX × Spotify design • v1.0.3-preview
      </footer>
    </div>
  );
}
