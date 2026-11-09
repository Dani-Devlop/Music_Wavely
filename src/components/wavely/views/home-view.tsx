"use client";

import Image from "next/image";
import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import { EqBars } from "../eq-bars";
import { SongRow } from "../song-row";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import { ALBUMS, PLAYLISTS, trackById, tracksOfAlbum } from "@/lib/wavely/data";
import { Button } from "@/components/ui/button";
import { useToast } from "@/hooks/use-toast";
import {
  ArrowRight,
  Cloud,
  Download,
  Heart,
  MoreHorizontal,
  Play,
  Smartphone,
  Sparkles,
} from "lucide-react";
import { cn } from "@/lib/utils";
import type { TrackOrigin } from "@/lib/wavely/types";

type HomeFilter = "all" | TrackOrigin;

const FILTERS: { id: HomeFilter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "local", label: "On device" },
  { id: "online", label: "Online" },
];

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

function seeAll(tab: "playlists" | "albums") {
  useWavely.getState().setLibraryTab(tab);
  useWavely.getState().setView("library");
}

/* ---------------------------------------------------------------- */
/* Curated banner card — "Discover weekly" style from the reference  */
/* ---------------------------------------------------------------- */
function CuratedCard({
  image,
  title,
  subtitle,
  onPlay,
  imagePosition = "right",
}: {
  image?: string;
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
      {/* artwork */}
      {image && (
        <Image
          src={image}
          alt=""
          fill
          sizes="(max-width: 640px) 86vw, 380px"
          className={cn("object-cover", imagePosition === "right" ? "object-right" : "object-center")}
        />
      )}
      {/* legibility gradient — text side */}
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

      {/* decorative sparkle for the AI card (no artwork) */}
      {!image && (
        <div className="absolute -right-6 top-1/2 -translate-y-1/2 opacity-90" aria-hidden="true">
          <Sparkles className="h-28 w-28 text-primary/50" strokeWidth={1} />
        </div>
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
            onClick={() => toast({ description: "Available offline in the full app" })}
            className="flex h-9 w-9 items-center justify-center rounded-full bg-black/30 text-foreground backdrop-blur transition hover:bg-black/50"
            aria-label={`Download ${title}`}
          >
            <Download className="h-4 w-4" />
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
/* Playlist list row — "Top daily playlists" style                   */
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
  origin: TrackOrigin;
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
            <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-primary/12 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wide text-primary">
              <Cloud className="h-2.5 w-2.5" /> Online
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
/* Home view                                                         */
/* ---------------------------------------------------------------- */
export function HomeView() {
  const playContext = useWavely((s) => s.playContext);
  const setView = useWavely((s) => s.setView);
  const currentTrack = useCurrentTrack();
  const [filter, setFilter] = useState<HomeFilter>("all");

  const playlists = useMemo(
    () => PLAYLISTS.filter((p) => filter === "all" || p.origin === filter),
    [filter],
  );

  const discoverMix = ["t01", "t13", "t26", "t09", "t31", "t22", "t17", "t28"];
  const jumpBackIds = ["t26", "t17", "t01", "t31", "t13"];

  return (
    <div className="mx-auto w-full max-w-md space-y-7 px-4 pb-10 pt-[max(1rem,env(safe-area-inset-top))] md:max-w-3xl md:px-8 lg:max-w-5xl">
      {/* ------- header: avatar + actions ------- */}
      <header className="flex items-start justify-between">
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
      </header>

      {/* ------- greeting ------- */}
      <div className="-mt-4">
        <p className="text-[11px] font-semibold uppercase tracking-[0.2em] text-muted-foreground">
          {greeting()}
        </p>
        <h1 className="mt-1 font-display text-3xl font-extrabold tracking-tight md:text-4xl">
          Hi, Dani
        </h1>
      </div>

      {/* ------- filter chips ------- */}
      <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 md:mx-0 md:px-0" role="tablist" aria-label="Filter music source">
        {FILTERS.map((f) => {
          const active = filter === f.id;
          return (
            <button
              key={f.id}
              role="tab"
              aria-selected={active}
              onClick={() => setFilter(f.id)}
              className={cn(
                "flex shrink-0 items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold transition-all",
                active
                  ? "bg-primary text-primary-foreground shadow-md shadow-primary/25"
                  : "border border-border bg-secondary/70 text-muted-foreground hover:text-foreground",
              )}
            >
              {f.id === "local" && <Smartphone className="h-3.5 w-3.5" />}
              {f.id === "online" && <Cloud className="h-3.5 w-3.5" />}
              {f.label}
            </button>
          );
        })}
      </div>

      {/* ------- curated & trending ------- */}
      <section>
        <SectionHeader title="Curated & trending" />
        <div className="no-scrollbar -mx-4 flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
          <CuratedCard
            image="/wavely/curated-1.png"
            title="Wavely Weekly"
            subtitle="Fresh picks built from what you play. Updated every Friday."
            onPlay={() => playContext("Wavely Weekly", discoverMix, 0)}
          />
          <CuratedCard
            title="Wavely AI DJ"
            subtitle="Ask for a playlist, song facts, or just say “surprise me”."
            onPlay={() => setView("ai")}
          />
          <CuratedCard
            image="/wavely/curated-2.png"
            title="Discover Mix"
            subtitle="A scan through genres you haven't touched yet."
            onPlay={() => playContext("Discover Mix", discoverMix.slice().reverse(), 0)}
          />
        </div>
      </section>

      {/* ------- top daily playlists ------- */}
      <section>
        <SectionHeader
          title="Top daily playlists"
          action={
            <Button variant="ghost" size="sm" className="text-xs text-muted-foreground" onClick={() => seeAll("playlists")}>
              See all
            </Button>
          }
        />
        <div className="space-y-0.5">
          {playlists.map((p) => {
            const cover =
              p.id === "pl1" ? "/covers/green-circuit.png"
              : p.id === "pl2" ? "/covers/deep-focus.png"
              : p.id === "pl3" ? "/covers/persian-echoes.png"
              : p.id === "pl4" ? "/covers/velvet-static.png"
              : p.id === "pl5" ? "/covers/neon-horizon.png"
              : "/covers/paper-planes.png";
            return (
              <PlaylistRow
                key={p.id}
                name={p.name}
                description={p.description}
                cover={cover}
                origin={p.origin}
                trackCount={p.trackIds.length}
                playing={currentTrack !== undefined && p.trackIds.includes(currentTrack.id)}
                onPlay={() => playContext(p.name, p.trackIds, 0)}
                onOpen={() => seeAll("playlists")}
              />
            );
          })}
          {playlists.length === 0 && (
            <p className="rounded-xl bg-wav-surface p-4 text-sm text-muted-foreground">
              Nothing here for this filter yet.
            </p>
          )}
        </div>
      </section>

      {/* ------- AI DJ strip (desktop, matches curated cards) ------- */}
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

      {/* ------- jump back in ------- */}
      <section>
        <SectionHeader title="Jump back in" />
        <div className="space-y-0.5">
          {jumpBackIds.map((id, i) => {
            const t = trackById.get(id)!;
            return (
              <SongRow
                key={id}
                track={t}
                index={i}
                showIndex
                onPlay={() => playContext("Jump back in", jumpBackIds, i)}
              />
            );
          })}
        </div>
      </section>

      {/* ------- new releases ------- */}
      <section>
        <SectionHeader
          title="New releases"
          action={
            <Button variant="ghost" size="sm" className="text-xs text-muted-foreground" onClick={() => seeAll("albums")}>
              See all
            </Button>
          }
        />
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          {[...ALBUMS].sort((a, b) => b.year - a.year).slice(0, 4).map((a) => (
            <button
              key={a.id}
              onClick={() => playContext(a.title, tracksOfAlbum(a.id).map((t) => t.id), 0)}
              className="group rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent"
            >
              <div className="relative mb-3 aspect-square overflow-hidden rounded-lg bg-secondary">
                <Image src={a.cover} alt={a.title} fill sizes="(max-width: 640px) 45vw, 220px" className="object-cover" />
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

      <footer className="flex items-center justify-center gap-2 pb-2 pt-2 text-xs text-muted-foreground">
        Wavely prototype • Musicolet UX × Spotify design • v1.0.3-preview
      </footer>
    </div>
  );
}
