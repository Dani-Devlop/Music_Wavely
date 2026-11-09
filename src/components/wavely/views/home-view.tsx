"use client";

import Image from "next/image";
import { useMemo } from "react";
import { motion } from "framer-motion";
import { EqBars } from "../eq-bars";
import { SongRow } from "../song-row";
import { SourceModeChips, OfflineBanner } from "../source-mode-chips";
import { useWavely, useCurrentTrack, useEffectiveMode, filterByMode } from "@/lib/wavely/store";
import { ALBUMS, FOLDERS, PLAYLISTS, TRACKS, albumCover, trackById, tracksOfAlbum } from "@/lib/wavely/data";
import { fmtLongTime } from "@/lib/wavely/data";
import { Button } from "@/components/ui/button";
import { useToast } from "@/hooks/use-toast";
import {
  ArrowRight,
  Cloud,
  Folder,
  Heart,
  Layers,
  MoreHorizontal,
  Play,
  Smartphone,
  Sparkles,
  WifiOff,
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

function seeAll(tab: "playlists" | "albums" | "folders") {
  useWavely.getState().setLibraryTab(tab);
  useWavely.getState().setView("library");
}

/* ---------------------------------------------------------------- */
/* Curated banner card — "Discover weekly" style from the reference  */
/* ---------------------------------------------------------------- */
function CuratedCard({
  image,
  badge,
  title,
  subtitle,
  onPlay,
  imagePosition = "right",
}: {
  image?: string;
  badge?: "online" | "ai" | "offline";
  title: string;
  subtitle: string;
  onPlay: () => void;
  imagePosition?: "right" | "full";
}) {
  const favorites = useWavely((s) => s.favorites);
  const toggleFavorite = useWavely((s) => s.toggleFavorite);
  const { toast } = useToast();
  const isFav = favorites.includes(`cur:${title}`);

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
          className={cn("object-cover", imagePosition === "right" ? "object-right" : "object-center")}
        />
      )}
      <div
        className={cn(
          "absolute inset-0",
          image
            ? imagePosition === "right"
              ? "bg-gradient-to-r from-background/95 via-background/70 to-transparent"
              : "bg-gradient-to-r from-background/90 via-background/55 to-background/20"
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
            badge === "offline" && "bg-amber-500/20 text-amber-300",
          )}
        >
          {badge === "online" && <Cloud className="h-3 w-3" />}
          {badge === "ai" && <Sparkles className="h-3 w-3" />}
          {badge === "offline" && <WifiOff className="h-3 w-3" />}
          {badge === "online" ? "Online" : badge === "ai" ? "AI" : "Offline"}
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
          <button
            onClick={() => toggleFavorite(`cur:${title}`)}
            className="flex h-9 w-9 items-center justify-center rounded-full bg-black/30 text-foreground backdrop-blur transition hover:bg-black/50"
            aria-label={`Favorite ${title}`}
          >
            <Heart className={cn("h-4 w-4", isFav && "fill-primary text-primary")} />
          </button>
          <button
            onClick={() => toast({ description: "Download starts in the full app" })}
            className="flex h-9 w-9 items-center justify-center rounded-full bg-black/30 text-foreground backdrop-blur transition hover:bg-black/50"
            aria-label={`Download ${title}`}
          >
            <ArrowRight className="hidden h-4 w-4" />
            <Folder className="h-4 w-4" />
          </button>
          <button
            onClick={() => toast({ description: "More options — in the full app" })}
            className="flex h-9 w-9 items-center justify-center rounded-full bg-black/30 text-foreground backdrop-blur transition hover:bg-black/50"
            aria-label={`More options for ${title}`}
          >
            <MoreHorizontal className="h-4 w-4" />
          </button>
        </div>
      </div>
    </motion.article>
  );
}

/* ---------------------------------------------------------------- */
/* Playlist list row — mixed origins get badges                      */
/* ---------------------------------------------------------------- */
function PlaylistRow({
  name,
  description,
  cover,
  origin,
  trackCount,
  playing,
  onPlay,
  onOpen,
}: {
  name: string;
  description: string;
  cover: string;
  origin: "local" | "online" | "mixed";
  trackCount: number;
  playing?: boolean;
  onPlay: () => void;
  onOpen: () => void;
}) {
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onOpen}
      onKeyDown={(e) => e.key === "Enter" && onOpen()}
      className="group flex items-center gap-3 rounded-xl p-2 text-left transition hover:bg-accent/60"
    >
      <div className="relative h-[52px] w-[52px] shrink-0 overflow-hidden rounded-xl bg-secondary">
        <Image src={cover} alt="" fill sizes="52px" className="object-cover" />
      </div>
      <div className="min-w-0 flex-1">
        <p className="flex items-center gap-1.5 truncate text-sm font-semibold">
          <span className="truncate">{name}</span>
          {origin === "online" && (
            <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-sky-400/12 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wide text-sky-300">
              <Cloud className="h-2.5 w-2.5" /> Online
            </span>
          )}
          {origin === "mixed" && (
            <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-primary/12 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wide text-primary">
              <Layers className="h-2.5 w-2.5" /> Mixed
            </span>
          )}
        </p>
        <p className="truncate text-xs text-muted-foreground">
          By Wavely • {trackCount} songs
        </p>
        <p className="truncate text-[11px] text-muted-foreground/70">{description}</p>
      </div>
      <button
        onClick={(e) => {
          e.stopPropagation();
          onPlay();
        }}
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-border text-foreground transition hover:border-primary hover:bg-primary hover:text-primary-foreground"
        aria-label={`Play ${name}`}
      >
        {playing ? <EqBars barClassName="bg-primary" /> : <Play className="h-4 w-4 fill-current" />}
      </button>
    </div>
  );
}

/* ---------------------------------------------------------------- */
/* Spotify-style quick tile (2-col grid, cover + label)              */
/* ---------------------------------------------------------------- */
function QuickTile({
  cover,
  title,
  playing,
  onClick,
}: {
  cover: string;
  title: string;
  playing?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="group flex items-center gap-3 overflow-hidden rounded-lg bg-wav-surface text-left transition hover:bg-accent"
    >
      <div className="relative h-14 w-14 shrink-0 overflow-hidden bg-secondary">
        <Image src={cover} alt="" fill sizes="56px" className="object-cover" />
      </div>
      <p className="min-w-0 flex-1 truncate pr-2 text-[13px] font-semibold leading-tight">{title}</p>
      {playing ? (
        <span className="mr-3 shrink-0">
          <EqBars />
        </span>
      ) : (
        <span className="mr-3 hidden h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-lg transition group-hover:opacity-100 sm:flex">
          <Play className="h-4 w-4 fill-primary-foreground" />
        </span>
      )}
    </button>
  );
}

/* ---------------------------------------------------------------- */
/* Home view                                                         */
/* ---------------------------------------------------------------- */
export function HomeView() {
  const playContext = useWavely((s) => s.playContext);
  const setView = useWavely((s) => s.setView);
  const currentTrack = useCurrentTrack();
  const mode = useEffectiveMode();
  const isOffline = useWavely((s) => s.isOffline);
  const { toast } = useToast();

  const playlists = useMemo(() => {
    if (mode === "all") return PLAYLISTS;
    if (mode === "local") return PLAYLISTS.filter((p) => p.origin === "local" || p.origin === "mixed");
    return PLAYLISTS.filter((p) => p.origin === "online" || p.origin === "mixed");
  }, [mode]);

  const jumpBackIds = useMemo(
    () =>
      filterByMode(
        ["t26", "t35", "t17", "t01", "t39", "t31", "t13"]
          .map((id) => trackById.get(id)!)
          .filter(Boolean),
        mode,
      ).map((t) => t.id),
    [mode],
  );

  const albums = useMemo(() => {
    const sorted = [...ALBUMS].sort((a, b) => b.year - a.year);
    if (mode === "all") return sorted.slice(0, 4);
    return filterByMode(sorted.flatMap((a) => tracksOfAlbum(a.id)), mode)
      .map((t) => ALBUMS.find((a) => a.id === t.albumId)!)
      .filter((a, i, arr) => a && arr.findIndex((x) => x.id === a.id) === i)
      .slice(0, 4);
  }, [mode]);

  const localTracks = useMemo(() => TRACKS.filter((t) => t.origin === "local"), []);
  const downloadedTracks = useMemo(() => TRACKS.filter((t) => t.downloaded), []);
  const localStats = useMemo(() => {
    const sec = localTracks.reduce((a, t) => a + t.duration, 0);
    return { count: localTracks.length, time: fmtLongTime(sec) };
  }, [localTracks]);

  const discoverMix = filterByMode(["t01", "t35", "t13", "t43", "t26", "t39", "t09", "t31", "t22", "t17"], "all");

  const playlistCover = (id: string) =>
    id === "pl1" ? "/covers/green-circuit.png"
    : id === "pl2" ? "/covers/deep-focus.png"
    : id === "pl3" ? "/covers/persian-echoes.png"
    : id === "pl4" ? "/covers/velvet-static.png"
    : id === "pl5" ? "/covers/neon-horizon.png"
    : id === "pl6" ? "/covers/online-violet-summer.png"
    : id === "pl7" ? "/covers/paper-planes.png"
    : "/covers/golden-hour.png";

  const eyebrow =
    mode === "local" ? `${greeting()} • Offline player` : mode === "online" ? `${greeting()} • Discover online` : greeting();

  return (
    <div className="mx-auto w-full max-w-md space-y-7 px-4 pb-10 md:max-w-3xl md:px-8 lg:max-w-5xl">
      {/* ------- sticky header: avatar, actions + source chips ------- */}
      <header className="sticky top-0 z-20 -mx-4 bg-background/85 px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))] backdrop-blur-xl md:-mx-8 md:px-8">
        <div className="flex items-center justify-between gap-3 pt-2">
          <button
            onClick={() => setView("settings")}
            className="relative h-12 w-12 overflow-hidden rounded-full ring-2 ring-primary/40 transition hover:ring-primary"
            aria-label="Open profile"
          >
            <Image src="/wavely/avatar.png" alt="Your profile" fill sizes="48px" className="object-cover" />
          </button>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setView("search")}
              className="flex h-11 w-11 items-center justify-center rounded-full bg-wav-elevated text-foreground transition hover:bg-accent"
              aria-label="Search"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" className="h-5 w-5" aria-hidden="true">
                <circle cx="11" cy="11" r="7" />
                <path d="m20 20-3.5-3.5" strokeLinecap="round" />
              </svg>
            </button>
            <button
              onClick={() => {
                useWavely.getState().setLibraryTab("favorites");
                setView("library");
              }}
              className="flex h-11 w-11 items-center justify-center rounded-full bg-wav-elevated text-foreground transition hover:bg-accent"
              aria-label="Favorites"
            >
              <Heart className="h-5 w-5" />
            </button>
          </div>
        </div>
        <SourceModeChips className="mt-3" />
      </header>

      <OfflineBanner />

      {/* ------- greeting ------- */}
      <div className="-mt-4">
        <p className="text-[11px] font-semibold uppercase tracking-[0.2em] text-muted-foreground">
          {eyebrow}
        </p>
        <h1 className="mt-1 font-display text-3xl font-extrabold tracking-tight md:text-4xl">
          Hi, Dani
        </h1>
      </div>

      {/* ------- jump back in (Spotify-style tiles) ------- */}
      <section>
        <SectionHeader title={mode === "online" ? "Pick up where you left off" : "Jump back in"} />
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {jumpBackIds.slice(0, 6).map((id) => {
            const t = trackById.get(id)!;
            return (
              <QuickTile
                key={id}
                cover={albumCover(t.albumId)}
                title={`${t.title} • ${t.artist}`}
                playing={currentTrack?.id === id}
                onClick={() => playContext("Jump back in", jumpBackIds, jumpBackIds.indexOf(id))}
              />
            );
          })}
        </div>
      </section>

      {/* ------- LOCAL MODE: offline hero ------- */}
      {mode === "local" && (
        <section>
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-primary/30 via-primary/10 to-transparent p-5"
          >
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-primary text-primary-foreground accent-glow">
                <Smartphone className="h-6 w-6" />
              </div>
              <div className="min-w-0 flex-1">
                <h3 className="font-display text-lg font-bold">Offline player ready</h3>
                <p className="mt-0.5 text-sm text-muted-foreground">
                  {localStats.count} songs on device + {downloadedTracks.length} saved from online
                  • {localStats.time} of music • zero internet needed
                </p>
              </div>
            </div>
            <div className="mt-4 flex flex-wrap items-center gap-2">
              <Button
                className="h-10 gap-2 rounded-full"
                onClick={() => {
                  const ids = filterByMode(TRACKS, "local").map((t) => t.id);
                  playContext("Offline shuffle", ids, Math.floor(Math.random() * ids.length));
                  useWavely.getState().toggleShuffle();
                }}
              >
                <Play className="h-4 w-4 fill-primary-foreground" /> Shuffle offline
              </Button>
              <Button variant="outline" className="h-10 gap-2 rounded-full" onClick={() => seeAll("folders")}>
                <Folder className="h-4 w-4" /> Browse folders
              </Button>
              <Button variant="ghost" className="h-10 rounded-full text-muted-foreground" onClick={() => setView("settings")}>
                Storage settings
              </Button>
            </div>
          </motion.div>
        </section>
      )}

      {/* ------- curated & trending (all / online) ------- */}
      {mode !== "local" && (
        <section>
          <SectionHeader title={mode === "online" ? "Trending now" : "Curated & trending"} />
          <div className="no-scrollbar -mx-4 flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
            <CuratedCard
              image="/wavely/curated-1.png"
              badge="ai"
              title="Wavely Weekly"
              subtitle="Fresh picks built from what you play — local and online together."
              onPlay={() => playContext("Wavely Weekly", discoverMix, 0)}
            />
            <CuratedCard
              badge="ai"
              title="Wavely AI DJ"
              subtitle="Ask for a playlist, song facts, or just say “surprise me”."
              onPlay={() => setView("ai")}
            />
            {mode === "online" && (
              <CuratedCard
                image="/covers/online-chrome-city.png"
                badge="online"
                title="Chrome City — full album stream"
                subtitle="Midnight Arcade's new synthpop LP, streaming in 320kbps."
                onPlay={() => playContext("Chrome City", tracksOfAlbum("al9").map((t) => t.id), 0)}
              />
            )}
            <CuratedCard
              image="/wavely/curated-2.png"
              title="Discover Mix"
              subtitle="A scan through genres you haven't touched yet."
              onPlay={() => playContext("Discover Mix", discoverMix.slice().reverse(), 0)}
            />
          </div>
        </section>
      )}

      {/* ------- top playlists (all modes, filtered) ------- */}
      <section>
        <SectionHeader
          title={mode === "local" ? "Your playlists" : "Top daily playlists"}
          action={
            <Button variant="ghost" size="sm" className="text-xs text-muted-foreground" onClick={() => seeAll("playlists")}>
              See all
            </Button>
          }
        />
        <div className="space-y-0.5">
          {playlists.map((p) => (
            <PlaylistRow
              key={p.id}
              name={p.name}
              description={p.description}
              cover={playlistCover(p.id)}
              origin={p.origin}
              trackCount={p.trackIds.length}
              playing={currentTrack !== undefined && p.trackIds.includes(currentTrack.id)}
              onPlay={() => playContext(p.name, p.trackIds, 0)}
              onOpen={() => seeAll("playlists")}
            />
          ))}
          {playlists.length === 0 && (
            <p className="rounded-xl bg-wav-surface p-4 text-sm text-muted-foreground">
              Nothing here for this filter yet.
            </p>
          )}
        </div>
      </section>

      {/* ------- on this device (all / local) ------- */}
      {mode !== "online" && (
        <section>
          <SectionHeader
            title="On this device"
            action={
              <Button variant="ghost" size="sm" className="text-xs text-muted-foreground" onClick={() => seeAll("folders")}>
                See all
              </Button>
            }
          />
          <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
            {FOLDERS.map((f) => {
              const short = f.split("/").filter(Boolean).slice(-1)[0];
              const count = TRACKS.filter((t) => t.folder === f).length;
              return (
                <button
                  key={f}
                  onClick={() => playContext(short, TRACKS.filter((t) => t.folder === f).map((t) => t.id), 0)}
                  className="flex shrink-0 items-center gap-2.5 rounded-xl bg-wav-surface px-4 py-3 text-left transition hover:bg-accent"
                >
                  <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/15 text-primary">
                    <Folder className="h-4 w-4" />
                  </span>
                  <span>
                    <span className="block text-sm font-semibold">/{short}</span>
                    <span className="block text-[11px] text-muted-foreground">{count} songs</span>
                  </span>
                </button>
              );
            })}
            {downloadedTracks.length > 0 && (
              <button
                onClick={() =>
                  playContext("Saved from online", downloadedTracks.map((t) => t.id), 0)
                }
                className="flex shrink-0 items-center gap-2.5 rounded-xl bg-primary/10 px-4 py-3 text-left ring-1 ring-primary/30 transition hover:bg-primary/15"
              >
                <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/20 text-primary">
                  <Layers className="h-4 w-4" />
                </span>
                <span>
                  <span className="block text-sm font-semibold">Wavely Downloads</span>
                  <span className="block text-[11px] text-muted-foreground">
                    {downloadedTracks.length} saved • /Music/Wavely
                  </span>
                </span>
              </button>
            )}
          </div>
        </section>
      )}

      {/* ------- AI DJ strip (desktop) ------- */}
      {mode !== "local" && (
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

      {/* ------- new releases / album grid ------- */}
      <section>
        <SectionHeader
          title={mode === "local" ? "Your albums" : "New releases"}
          action={
            <Button variant="ghost" size="sm" className="text-xs text-muted-foreground" onClick={() => seeAll("albums")}>
              See all
            </Button>
          }
        />
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          {albums.map((a) => (
            <button
              key={a.id}
              onClick={() => playContext(a.title, tracksOfAlbum(a.id).map((t) => t.id), 0)}
              className="group rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent"
            >
              <div className="relative mb-3 aspect-square overflow-hidden rounded-lg bg-secondary">
                <Image src={a.cover} alt={a.title} fill sizes="(max-width: 640px) 45vw, 220px" className="object-cover" />
                {a.origin === "online" && (
                  <span className="absolute left-2 top-2 inline-flex items-center gap-1 rounded-full bg-black/60 px-2 py-1 text-[9px] font-bold uppercase tracking-wide text-sky-300 backdrop-blur">
                    <Cloud className="h-3 w-3" /> Stream
                  </span>
                )}
                <span className="absolute bottom-2 right-2 flex h-11 w-11 translate-y-2 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-xl transition-all group-hover:translate-y-0 group-hover:opacity-100">
                  <Play className="h-5 w-5 fill-primary-foreground" />
                </span>
              </div>
              <p className="truncate text-sm font-semibold">{a.title}</p>
              <p className="truncate text-xs text-muted-foreground">{a.year} • {a.artist}</p>
            </button>
          ))}
        </div>
      </section>

      <footer className="flex flex-wrap items-center justify-center gap-x-2 gap-y-1 pb-2 pt-2 text-center text-xs text-muted-foreground">
        {isOffline ? (
          <>
            <WifiOff className="h-3 w-3" /> Offline player • all {localStats.count + downloadedTracks.length} songs available
          </>
        ) : (
          <>Wavely prototype • Musicolet UX × Spotify design • v1.0.3-preview</>
        )}
      </footer>
    </div>
  );
}
