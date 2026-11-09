"use client";

import Image from "next/image";
import { useMemo } from "react";
import { motion } from "framer-motion";
import { EqBars } from "../eq-bars";
import { SongRow } from "../song-row";
import { OfflineBanner } from "../source-mode-chips";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import { ALBUMS, PLAYLISTS, TRACKS, fmtLongTime, trackById, tracksOfAlbum } from "@/lib/wavely/data";
import type { LibraryTab, SongFilter, SongSortMode } from "@/lib/wavely/types";
import { Button } from "@/components/ui/button";
import {
  ArrowRight,
  Ban,
  ChevronRight,
  ClockPlus,
  Cloud,
  CloudOff,
  Disc3,
  Flame,
  Folder,
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

/** Jumps into the Library with a specific tab / sort / filter pre-applied. */
function openLibrary(opts: { tab: LibraryTab; sort?: SongSortMode; filter?: SongFilter }) {
  const s = useWavely.getState();
  s.setLibraryTab(opts.tab);
  if (opts.sort) s.setSongSort(opts.sort);
  s.setSongFilter(opts.filter ?? "all");
  s.setView("library");
}

/** Is this track a real file on the device (local scan or downloaded)? */
const onDevice = (id: string) => {
  const t = trackById.get(id);
  return !!t && (t.origin === "local" || !!t.downloaded);
};

/* ---------------------------------------------------------------- */
/* Compact header — avatar + greeting + search, one row, no waste    */
/* ---------------------------------------------------------------- */
function HomeHeader() {
  const setView = useWavely((s) => s.setView);
  return (
    <header className="sticky top-0 z-20 -mx-4 bg-background/85 px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))] backdrop-blur-xl md:-mx-8 md:px-8">
      <div className="flex items-center gap-3 pt-1">
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
          className="group relative flex min-h-44 flex-col justify-between overflow-hidden rounded-2xl bg-gradient-to-br from-primary/45 via-primary/18 to-transparent p-4 text-left"
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
/* LOCAL world — Musicolet-style flat rows                           */
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
        "flex w-full items-center gap-4 rounded-xl px-2.5 py-2.5 text-left transition hover:bg-accent/60",
        active && "bg-accent/40",
      )}
    >
      <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary/12 text-primary">
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
      className="flex items-center gap-3 rounded-xl bg-wav-surface px-3 py-3 text-left transition hover:bg-accent"
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
  const wavelyDownloads = TRACKS.filter((t) => t.downloaded).length;

  return (
    <section>
      <div className="mb-2 flex items-center gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/12 text-primary">
          <Smartphone className="h-5 w-5" />
        </span>
        <div className="min-w-0 flex-1">
          <h2 className="font-display text-lg font-bold tracking-tight md:text-xl">Your Library</h2>
          <p className="truncate text-[11px] text-muted-foreground">
            On this device • {deviceCount} songs • {deviceTime}
            {wavelyDownloads > 0 && ` • ${wavelyDownloads} saved from online`}
          </p>
        </div>
      </div>

      <div className="rounded-2xl bg-wav-surface/50 p-1.5">
        <MusicoletRow
          icon={LibraryBig}
          label="All songs"
          detail={`${deviceCount} songs on device`}
          onClick={() => openLibrary({ tab: "songs", sort: "title-asc" })}
        />
        <MusicoletRow
          icon={Heart}
          label="Favorites"
          detail={`${deviceFavorites} songs`}
          onClick={() => openLibrary({ tab: "favorites" })}
        />
        <MusicoletRow
          icon={ClockPlus}
          label="Recently added"
          detail="newest imports first"
          onClick={() => openLibrary({ tab: "songs", sort: "date-added" })}
        />
        <MusicoletRow
          icon={History}
          label="Recently played"
          detail={`${deviceHistory} in device history`}
          onClick={() => openLibrary({ tab: "history" })}
        />
        <MusicoletRow
          icon={Flame}
          label="Most played"
          detail="sorted by play count"
          onClick={() => openLibrary({ tab: "songs", sort: "play-count" })}
        />
        <MusicoletRow
          icon={Ban}
          label="Not played"
          detail={`${notPlayedCount} songs waiting for you`}
          onClick={() => openLibrary({ tab: "songs", filter: "not-played" })}
        />
      </div>

      <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
        <QuickLink icon={Disc3} label="Albums" count={`${deviceAlbums}`} onClick={() => openLibrary({ tab: "albums" })} />
        <QuickLink icon={MicVocal} label="Artists" count="8 on device" onClick={() => openLibrary({ tab: "artists" })} />
        <QuickLink icon={Folder} label="Folders" count="Music · Downloads · FLAC" onClick={() => openLibrary({ tab: "folders" })} />
        <QuickLink icon={ListPlus} label="Playlists" count={`${PLAYLISTS.length}`} onClick={() => openLibrary({ tab: "playlists" })} />
        <QuickLink icon={ListMusic} label="Queues" count={`${queues.length}/20`} onClick={() => openLibrary({ tab: "queues" })} />
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
      </div>
    </section>
  );
}

/* ---------------------------------------------------------------- */
/* ONLINE world — Spotify-style discovery                            */
/* ---------------------------------------------------------------- */
function CuratedCard({
  image,
  badge,
  title,
  subtitle,
  onPlay,
}: {
  image?: string;
  badge?: "online" | "ai";
  title: string;
  subtitle: string;
  onPlay: () => void;
}) {
  return (
    <motion.article
      whileTap={{ scale: 0.985 }}
      className={cn(
        "relative aspect-[16/10] w-[86%] max-w-[420px] shrink-0 snap-center overflow-hidden rounded-2xl sm:aspect-[2.3/1] sm:w-[380px]",
        image ? "bg-wav-elevated" : "bg-gradient-to-br from-primary/45 via-primary/15 to-wav-elevated",
      )}
    >
      {image && (
        <Image
          src={image}
          alt=""
          fill
          sizes="(max-width: 640px) 86vw, 380px"
          className="object-cover object-right"
        />
      )}
      <div
        className={cn(
          "absolute inset-0",
          image
            ? "bg-gradient-to-r from-background/95 via-background/70 to-transparent"
            : "bg-gradient-to-r from-background/80 via-background/40 to-transparent",
        )}
      />

      {!image && (
        <div className="absolute -right-6 top-1/2 -translate-y-1/2 opacity-90" aria-hidden="true">
          <Sparkles className="h-28 w-28 text-primary/50" strokeWidth={1} />
        </div>
      )}

      {badge && (
        <span
          className={cn(
            "absolute left-3 top-3 inline-flex items-center gap-1 rounded-full px-2 py-1 text-[9px] font-bold uppercase tracking-widest backdrop-blur",
            badge === "online" && "bg-sky-400/20 text-sky-200",
            badge === "ai" && "bg-primary/25 text-primary",
          )}
        >
          {badge === "online" && <Cloud className="h-3 w-3" />}
          {badge === "ai" && <Sparkles className="h-3 w-3" />}
          {badge === "online" ? "Online" : "AI"}
        </span>
      )}

      <div className="relative flex h-full flex-col justify-between p-4 sm:p-5">
        <div className="max-w-[62%]">
          <h3 className="font-display text-base font-bold leading-tight sm:text-lg">{title}</h3>
          <p className="mt-1 line-clamp-2 text-xs leading-snug text-muted-foreground sm:text-[13px]">
            {subtitle}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={onPlay}
            className="flex h-11 w-11 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition hover:scale-105 hover:bg-wav-accent-hover active:scale-95"
            aria-label={`Play ${title}`}
          >
            <Play className="ml-0.5 h-5 w-5 fill-primary-foreground" />
          </button>
        </div>
      </div>
    </motion.article>
  );
}

function ReleaseCard({
  cover,
  title,
  meta,
  playing,
  onPlay,
}: {
  cover: string;
  title: string;
  meta: string;
  playing?: boolean;
  onPlay: () => void;
}) {
  return (
    <button
      onClick={onPlay}
      className="group w-40 shrink-0 snap-start rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent"
    >
      <div className="relative mb-3 aspect-square overflow-hidden rounded-lg bg-secondary">
        <Image src={cover} alt={title} fill sizes="160px" className="object-cover" />
        <span className="absolute left-2 top-2 inline-flex items-center gap-1 rounded-full bg-black/60 px-2 py-1 text-[9px] font-bold uppercase tracking-wide text-sky-300 backdrop-blur">
          <Cloud className="h-3 w-3" /> Online
        </span>
        <span className="absolute bottom-2 right-2 flex h-11 w-11 translate-y-2 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-xl transition-all group-hover:translate-y-0 group-hover:opacity-100">
          {playing ? <EqBars barClassName="bg-primary-foreground" /> : <Play className="h-5 w-5 fill-primary-foreground" />}
        </span>
      </div>
      <p className="truncate text-sm font-semibold">{title}</p>
      <p className="truncate text-xs text-muted-foreground">{meta}</p>
    </button>
  );
}

function OnlineSection() {
  const playContext = useWavely((s) => s.playContext);
  const setView = useWavely((s) => s.setView);
  const isOffline = useWavely((s) => s.isOffline);
  const cachedIds = useWavely((s) => s.cachedIds);
  const currentTrack = useCurrentTrack();

  const onlineTracks = useMemo(() => TRACKS.filter((t) => t.origin === "online"), []);
  const topStreams = useMemo(
    () => [...onlineTracks].sort((a, b) => b.playCount - a.playCount).slice(0, 5),
    [onlineTracks],
  );
  const newReleases = useMemo(() => ALBUMS.filter((a) => a.origin === "online"), []);
  const cachedTracks = useMemo(
    () => cachedIds.map((id) => trackById.get(id)!).filter(Boolean),
    [cachedIds],
  );
  const discoverMix = ["t01", "t35", "t13", "t43", "t26", "t39", "t09", "t31", "t22", "t17"];

  return (
    <section>
      <div className="mb-3 flex items-center gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-sky-400/12 text-sky-300">
          <Cloud className="h-5 w-5" />
        </span>
        <div className="min-w-0 flex-1">
          <h2 className="font-display text-lg font-bold tracking-tight md:text-xl">Discover Online</h2>
          <p className="truncate text-[11px] text-muted-foreground">
            Streaming catalogue • up to FLAC • separate from your device library
          </p>
        </div>
        {!isOffline && (
          <Button
            variant="ghost"
            size="sm"
            className="text-xs text-muted-foreground"
            onClick={() => setView("search")}
          >
            Search
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
        <div className="space-y-6">
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
              <CuratedCard
                image="/covers/online-chrome-city.png"
                badge="online"
                title="Chrome City — full album stream"
                subtitle="Midnight Arcade's new synthpop LP, streaming in 320kbps."
                onPlay={() => playContext("Chrome City", tracksOfAlbum("al9").map((t) => t.id), 0)}
              />
            </div>
          </div>

          {/* new releases */}
          <div>
            <h3 className="mb-2 text-sm font-bold text-muted-foreground">New releases</h3>
            <div className="no-scrollbar -mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
              {newReleases.map((a) => (
                <ReleaseCard
                  key={a.id}
                  cover={a.cover}
                  title={a.title}
                  meta={`${a.year} • ${a.artist}`}
                  playing={currentTrack !== undefined && tracksOfAlbum(a.id).some((t) => t.id === currentTrack.id)}
                  onPlay={() => playContext(a.title, tracksOfAlbum(a.id).map((t) => t.id), 0)}
                />
              ))}
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
    <div className="mx-auto w-full max-w-md space-y-7 px-4 pb-10 md:max-w-3xl md:px-8 lg:max-w-5xl">
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

      {/* online world — Spotify style */}
      <OnlineSection />

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
