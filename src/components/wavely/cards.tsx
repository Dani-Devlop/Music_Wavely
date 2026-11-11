"use client";

import Image from "next/image";
import { motion } from "framer-motion";
import { Cloud, MoreHorizontal, Play, Sparkles } from "lucide-react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { EqBars } from "./eq-bars";
import { cn } from "@/lib/utils";

/* ------------------------------------------------------------------ */
/* Genre → colour identity (Latest releases cards, search categories)  */
/* ------------------------------------------------------------------ */
const GENRE_TINTS: Record<string, string> = {
  Synthwave: "from-fuchsia-500/35 via-fuchsia-500/12 to-transparent",
  Synthpop: "from-violet-500/35 via-violet-500/12 to-transparent",
  "Dream Pop": "from-rose-500/35 via-rose-500/12 to-transparent",
  Pop: "from-amber-400/35 via-amber-400/12 to-transparent",
  Electronic: "from-emerald-500/35 via-emerald-500/12 to-transparent",
  "Lo-Fi": "from-teal-500/35 via-teal-500/12 to-transparent",
  Rock: "from-red-500/35 via-red-500/12 to-transparent",
  "Indie Folk": "from-lime-500/35 via-lime-500/12 to-transparent",
  World: "from-orange-500/35 via-orange-500/12 to-transparent",
  Alternative: "from-pink-500/35 via-pink-500/12 to-transparent",
};

/** Soft colour wash for a card, keyed by the album's genre. */
export const genreTint = (genre: string) =>
  GENRE_TINTS[genre] ?? "from-primary/25 via-primary/10 to-transparent";

/* ------------------------------------------------------------------ */
/* Section header — bigger, bolder, with an optional "See all" link     */
/* (Spotify pages 5 & 8: heavy title, small uppercase action on the end) */
/* ------------------------------------------------------------------ */
export function SectionHead({
  title,
  hint,
  right,
  onSeeAll,
  expanded = false,
  size = "lg",
}: {
  title: string;
  hint?: string;
  /** custom right-side node (segmented chips, badges…), sits before See all */
  right?: React.ReactNode;
  /** pass to render the See all / Show less link */
  onSeeAll?: () => void;
  expanded?: boolean;
  size?: "lg" | "md";
}) {
  return (
    <div className="mb-3">
      {/* title + See all row — custom right node drops BELOW the title on mobile
          (Spotify mobile: chips scroll under the header, never squeeze the title) */}
      <div className="flex items-end justify-between gap-3">
        <div className="min-w-0">
          <h2
            className={cn(
              "font-display font-extrabold tracking-tight",
              size === "lg" ? "text-xl md:text-2xl" : "text-lg md:text-xl",
            )}
          >
            {title}
          </h2>
          {hint && <p className="mt-0.5 truncate text-[11px] text-muted-foreground">{hint}</p>}
        </div>
        <div className="hidden shrink-0 items-center gap-2 sm:flex">
          {right}
          {onSeeAll && (
            <button
              onClick={onSeeAll}
              className="text-[11px] font-bold uppercase tracking-widest text-muted-foreground transition hover:text-foreground"
              aria-pressed={expanded}
            >
              {expanded ? "Show less" : "See all"}
            </button>
          )}
        </div>
        {/* mobile: only the See all link sits beside the title */}
        {onSeeAll && (
          <button
            onClick={onSeeAll}
            className="shrink-0 text-[11px] font-bold uppercase tracking-widest text-muted-foreground transition hover:text-foreground sm:hidden"
            aria-pressed={expanded}
          >
            {expanded ? "Show less" : "See all"}
          </button>
        )}
      </div>
      {right && (
        <div className="no-scrollbar mt-2.5 flex gap-2 overflow-x-auto sm:hidden">{right}</div>
      )}
    </div>
  );
}

/** Wide Spotify-style banner card used in "Made for you" rails. */
export function CuratedCard({
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

/** Square album card for release rails — optional age meta ("3d ago").
 *  `fluid`: on md+ the rail becomes an auto-fill grid → card fills the cell.
 *  `cover` is optional: without one an AI gradient tile is rendered.
 *  `rank` renders a chart position chip ("Top players" style cards).
 *  The play FAB is hover-revealed on pointer devices and always visible on
 *  touch devices (phones + tablets use the desktop grid without hover). */
export function ReleaseCard({
  cover,
  title,
  meta,
  // default "online" keeps the streaming badge for callers that don't opt out (Explore)
  badge = "online",
  playing,
  fluid,
  fill,
  rank,
  onPlay,
}: {
  cover?: string;
  title: string;
  meta: string;
  badge?: "online" | "ai" | "none";
  playing?: boolean;
  fluid?: boolean;
  /** stretch to the full grid cell (See-all grids) instead of the w-40 rail card */
  fill?: boolean;
  rank?: number;
  onPlay: () => void;
}) {
  return (
    <button
      onClick={onPlay}
      className={cn(
        "group w-40 shrink-0 snap-start rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent",
        fluid && "md:w-auto md:snap-none",
        fill && "w-full md:w-auto",
      )}
    >
      <div className="relative mb-3 aspect-square overflow-hidden rounded-lg bg-secondary">
        {cover ? (
          <Image src={cover} alt={title} fill sizes="160px" className="object-cover" />
        ) : (
          <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-primary/50 via-primary/15 to-transparent">
            <Sparkles className="h-10 w-10 text-primary" strokeWidth={1.2} aria-hidden="true" />
          </div>
        )}
        {badge === "online" && (
          <span className="absolute left-2 top-2 inline-flex items-center gap-1 rounded-full bg-black/60 px-2 py-1 text-[9px] font-bold uppercase tracking-wide text-sky-300 backdrop-blur">
            <Cloud className="h-3 w-3" /> Online
          </span>
        )}
        {badge === "ai" && (
          <span className="absolute left-2 top-2 inline-flex items-center gap-1 rounded-full bg-primary/25 px-2 py-1 text-[9px] font-bold uppercase tracking-wide text-primary backdrop-blur">
            <Sparkles className="h-3 w-3" /> AI mix
          </span>
        )}
        {typeof rank === "number" && (
          <span
            className={cn(
              "absolute right-2 top-2 flex h-6 min-w-6 items-center justify-center rounded-full px-1.5 font-display text-xs font-extrabold tabular-nums backdrop-blur",
              rank === 1
                ? "bg-primary text-primary-foreground shadow-lg shadow-primary/40"
                : "bg-black/60 text-foreground",
            )}
            aria-label={`Rank ${rank}`}
          >
            {rank}
          </span>
        )}
        <span className="absolute bottom-2 right-2 flex h-11 w-11 translate-y-2 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-xl transition-all group-hover:translate-y-0 group-hover:opacity-100 [@media(hover:none)]:translate-y-0 [@media(hover:none)]:opacity-100">
          {playing ? <EqBars barClassName="bg-primary-foreground" /> : <Play className="h-5 w-5 fill-primary-foreground" />}
        </span>
      </div>
      <p className="truncate text-sm font-semibold">{title}</p>
      <p className="truncate text-xs text-muted-foreground">{meta}</p>
    </button>
  );
}

/** The ⋯ affordance of LatestReleaseCard — a DropdownMenu the caller fills. */
export function CardMenu({
  label,
  children,
  align = "end",
}: {
  label: string;
  children: React.ReactNode;
  align?: "start" | "center" | "end";
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <span
          role="button"
          tabIndex={0}
          aria-label={label}
          onClick={(e) => e.stopPropagation()}
          onKeyDown={(e) => e.stopPropagation()}
          className="flex h-9 w-9 items-center justify-center rounded-full text-white/85 transition hover:bg-white/15 hover:text-white"
        >
          <MoreHorizontal className="h-4.5 w-4.5" />
        </span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align={align} onClick={(e) => e.stopPropagation()} className="w-56 rounded-xl">
        {children}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/**
 * Spotify page 4 "Latest releases" card — big, coloured by genre tint, with
 * a Preview pill, a green play FAB and a ⋯ menu (caller supplies the items).
 */
export function LatestReleaseCard({
  cover,
  title,
  meta,
  tint,
  playing,
  onPlay,
  onPreview,
  menu,
}: {
  cover?: string;
  title: string;
  meta: string;
  /** gradient wash from genreTint() — keeps every release recognisable */
  tint?: string;
  playing?: boolean;
  /** whole-card tap (mobile friendly) */
  onPlay: () => void;
  /** the Preview pill — 30-sec feel in the real app */
  onPreview: () => void;
  /** dropdown menu items rendered inside CardMenu */
  menu?: React.ReactNode;
}) {
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onPlay}
      onKeyDown={(e) => {
        if (e.key === "Enter") onPlay();
      }}
      className={cn(
        "group relative w-64 shrink-0 snap-start overflow-hidden rounded-2xl bg-wav-surface text-left transition hover:bg-accent md:w-auto",
      )}
    >
      {/* genre colour wash bleeding from the top */}
      <span
        className={cn("absolute inset-x-0 top-0 h-28 bg-gradient-to-b", tint)}
        aria-hidden="true"
      />
      <div className="relative p-3">
        <div className="relative mb-3 aspect-square overflow-hidden rounded-xl bg-secondary shadow-lg">
          {cover ? (
            <Image src={cover} alt={title} fill sizes="260px" className="object-cover" />
          ) : (
            <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-primary/50 via-primary/15 to-transparent">
              <Sparkles className="h-12 w-12 text-primary" strokeWidth={1.2} aria-hidden="true" />
            </div>
          )}
          {playing && (
            <span className="absolute inset-0 flex items-center justify-center bg-black/45">
              <EqBars barClassName="bg-white" />
            </span>
          )}
        </div>
        <p className="truncate text-[15px] font-bold leading-tight">{title}</p>
        <p className="truncate text-xs text-muted-foreground">{meta}</p>
        <div className="mt-3 flex items-center gap-2">
          <button
            onClick={(e) => {
              e.stopPropagation();
              onPreview();
            }}
            className="flex h-9 shrink-0 items-center gap-1.5 rounded-full border border-border bg-background/40 px-4 text-xs font-bold text-foreground transition hover:border-primary/60 hover:bg-primary/10 hover:text-primary active:scale-95"
            aria-label={`Preview ${title}`}
          >
            <Play className="h-3.5 w-3.5 fill-current" /> Preview
          </button>
          <span className="flex-1" />
          {menu}
        </div>
      </div>
    </div>
  );
}

/**
 * Spotify page 5 "Start listening" tile — compact cover-left strip with a
 * hover-revealed play FAB (always visible on touch devices).
 */
export function StartTile({
  cover,
  title,
  gradient,
  icon: Icon,
  onPlay,
}: {
  cover?: string;
  title: string;
  /** solid gradient tile (used when there is no cover art, e.g. Liked songs) */
  gradient?: string;
  icon?: React.ElementType;
  onPlay: () => void;
}) {
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onPlay}
      onKeyDown={(e) => {
        if (e.key === "Enter") onPlay();
      }}
      className="group relative flex h-16 cursor-pointer items-center overflow-hidden rounded-lg bg-wav-surface/80 text-left transition hover:bg-accent focus-visible:bg-accent/70 focus-visible:outline-none"
      aria-label={`Play ${title}`}
    >
      <span className="relative block h-full w-16 shrink-0 overflow-hidden">
        {cover ? (
          <Image src={cover} alt="" fill sizes="64px" className="object-cover" />
        ) : (
          <span
            className={cn(
              "absolute inset-0 flex items-center justify-center bg-gradient-to-br",
              gradient ?? "from-primary/45 via-primary/15 to-transparent",
            )}
          >
            {Icon && <Icon className="h-6 w-6 fill-current text-white drop-shadow" />}
          </span>
        )}
      </span>
      <span className="min-w-0 flex-1 truncate px-3 text-[13px] font-bold leading-snug md:pr-12">
        {title}
      </span>
      {/* tile itself plays on tap — the FAB is a hover affordance only (pointer devices) */}
      <span
        role="button"
        tabIndex={-1}
        onClick={(e) => {
          e.stopPropagation();
          onPlay();
        }}
        className="absolute right-2.5 top-1/2 flex h-10 w-10 -translate-y-1/2 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-lg transition-all hover:scale-105 active:scale-95 md:group-hover:opacity-100"
        aria-hidden="true"
      >
        <Play className="ml-0.5 h-4 w-4 fill-primary-foreground" />
      </span>
    </div>
  );
}
