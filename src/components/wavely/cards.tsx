"use client";

import Image from "next/image";
import { motion } from "framer-motion";
import { Cloud, Play, Sparkles } from "lucide-react";
import { EqBars } from "./eq-bars";
import { cn } from "@/lib/utils";

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
 *  `cover` is optional: without one an AI gradient tile is rendered. */
export function ReleaseCard({
  cover,
  title,
  meta,
  // default "online" keeps the streaming badge for callers that don't opt out (Explore)
  badge = "online",
  playing,
  fluid,
  onPlay,
}: {
  cover?: string;
  title: string;
  meta: string;
  badge?: "online" | "ai";
  playing?: boolean;
  fluid?: boolean;
  onPlay: () => void;
}) {
  return (
    <button
      onClick={onPlay}
      className={cn(
        "group w-40 shrink-0 snap-start rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent",
        fluid && "md:w-auto md:snap-none",
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
        <span className="absolute bottom-2 right-2 flex h-11 w-11 translate-y-2 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-xl transition-all group-hover:translate-y-0 group-hover:opacity-100">
          {playing ? <EqBars barClassName="bg-primary-foreground" /> : <Play className="h-5 w-5 fill-primary-foreground" />}
        </span>
      </div>
      <p className="truncate text-sm font-semibold">{title}</p>
      <p className="truncate text-xs text-muted-foreground">{meta}</p>
    </button>
  );
}
