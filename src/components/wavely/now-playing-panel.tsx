"use client";

import Image from "next/image";
import { useState } from "react";
import { motion } from "framer-motion";
import { useWavely, useCurrentTrack, useActiveQueue } from "@/lib/wavely/store";
import { albumCover, fmtTime } from "@/lib/wavely/data";
import { LyricsPanel } from "./lyrics-panel";
import { EqBars } from "./eq-bars";
import { Button } from "@/components/ui/button";
import { Slider } from "@/components/ui/slider";
import { useToast } from "@/hooks/use-toast";
import {
  Gauge,
  Heart,
  ListMusic,
  Mic2,
  Moon,
  Pause,
  Play,
  Repeat,
  Repeat1,
  Shuffle,
  SkipBack,
  SkipForward,
  SlidersHorizontal,
  X,
} from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Spotify-style "Now playing" side panel (desktop + tablet shell).
 * Lives on the LEFT of the screen next to the nav sidebar — opened with the
 * mic button in the player bar instead of the full-screen takeover.
 * The header mic toggles art ↔ lyrics, exactly like the phone full-screen view.
 */
export function NowPlayingPanel() {
  const setOpen = useWavely((s) => s.setNowPlayingPanelOpen);
  const track = useCurrentTrack();
  const queue = useActiveQueue();
  const isPlaying = useWavely((s) => s.isPlaying);
  const togglePlay = useWavely((s) => s.togglePlay);
  const next = useWavely((s) => s.next);
  const prev = useWavely((s) => s.prev);
  const position = useWavely((s) => s.position);
  const seek = useWavely((s) => s.seek);
  const shuffle = useWavely((s) => s.shuffle);
  const toggleShuffle = useWavely((s) => s.toggleShuffle);
  const repeat = useWavely((s) => s.repeat);
  const cycleRepeat = useWavely((s) => s.cycleRepeat);
  const favorites = useWavely((s) => s.favorites);
  const toggleFavorite = useWavely((s) => s.toggleFavorite);
  const speed = useWavely((s) => s.speed);
  const setSpeed = useWavely((s) => s.setSpeed);
  const sleepEndsAt = useWavely((s) => s.sleepEndsAt);
  const setQueueSheetOpen = useWavely((s) => s.setQueueSheetOpen);
  const setEqOpen = useWavely((s) => s.setEqOpen);
  const setSleepTimerOpen = useWavely((s) => s.setSleepTimerOpen);

  const [showLyrics, setShowLyrics] = useState(false);
  const { toast } = useToast();

  const fnRow = [
    {
      icon: ListMusic,
      label: "Queue",
      active: false,
      onClick: () => setQueueSheetOpen(true),
    },
    {
      icon: SlidersHorizontal,
      label: "Equalizer",
      active: false,
      onClick: () => setEqOpen(true),
    },
    {
      icon: Moon,
      label: "Sleep",
      active: !!sleepEndsAt,
      onClick: () => setSleepTimerOpen(true),
    },
    {
      icon: Gauge,
      label: speed === 1 ? "Speed" : `${speed}×`,
      active: speed !== 1,
      onClick: () => {
        const speeds = [0.75, 1, 1.25, 1.5, 2];
        const i = speeds.indexOf(speed);
        const v = speeds[(i + 1) % speeds.length];
        setSpeed(v);
        toast({ description: `Playback speed: ${v}×` });
      },
    },
  ];

  return (
    <motion.aside
      initial={{ opacity: 0, x: -28 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: -28 }}
      transition={{ type: "spring", damping: 30, stiffness: 300 }}
      className="wavely-scroll hidden h-full w-[236px] shrink-0 flex-col overflow-hidden rounded-2xl bg-sidebar md:flex xl:w-[300px]"
      role="complementary"
      aria-label="Now playing panel"
    >
      {/* header */}
      <header className="flex shrink-0 items-center gap-1 px-3 pb-1 pt-3.5">
        <Button
          variant="ghost"
          size="icon"
          className={cn("h-8 w-8 rounded-full", showLyrics && "text-primary")}
          onClick={() => setShowLyrics((v) => !v)}
          aria-label={showLyrics ? "Show cover" : "Show lyrics"}
          aria-pressed={showLyrics}
          title="Lyrics"
        >
          <Mic2 className="h-4 w-4" />
        </Button>
        <p className="min-w-0 flex-1 truncate text-center text-xs font-bold uppercase tracking-widest text-muted-foreground">
          Now playing
        </p>
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8 rounded-full"
          onClick={() => setOpen(false)}
          aria-label="Close now playing panel"
        >
          <X className="h-4 w-4" />
        </Button>
      </header>

      {!track ? (
        <div className="flex flex-1 items-center justify-center px-6 text-center text-sm text-muted-foreground">
          Nothing playing yet — pick a song and it will show up here.
        </div>
      ) : (
        <div className="flex min-h-0 flex-1 flex-col px-3.5 pb-3.5">
          {showLyrics ? (
            /* lyrics mode — fixed area with soft fades so lines never clip */
            <div className="relative mt-2 min-h-0 flex-1">
              <LyricsPanel />
              <div className="pointer-events-none absolute inset-x-0 top-0 z-10 h-8 bg-gradient-to-b from-sidebar/90 to-transparent" />
              <div className="pointer-events-none absolute inset-x-0 bottom-0 z-10 h-10 bg-gradient-to-t from-sidebar/90 to-transparent" />
            </div>
          ) : (
            <>
              {/* playing-from context */}
              <p className="mt-1 shrink-0 px-0.5 text-[10px] font-semibold uppercase tracking-[0.18em] text-muted-foreground/80">
                Playing from
              </p>
              <p className="shrink-0 truncate px-0.5 text-[13px] font-semibold">
                {queue?.name ?? "Main Queue"}
              </p>

              {/* cover art — fills remaining space, never overflows */}
              <motion.div
                key={track.id}
                initial={{ opacity: 0, scale: 0.96 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ duration: 0.3, ease: "easeOut" }}
                className="relative mt-2.5 min-h-0 flex-1 overflow-hidden rounded-xl cover-shadow"
              >
                <Image
                  src={albumCover(track.albumId)}
                  alt={`${track.album} cover art`}
                  fill
                  sizes="300px"
                  className="object-cover"
                  priority
                />
              </motion.div>
            </>
          )}

          {/* title + favorite */}
          <div className="mt-3 flex shrink-0 items-center gap-2">
            <div className="min-w-0 flex-1">
              <h2 className="truncate font-display text-[15px] font-bold leading-tight">
                {track.title}
              </h2>
              <p className="truncate text-xs text-muted-foreground">{track.artist}</p>
            </div>
            <Button
              variant="ghost"
              size="icon"
              className="h-8 w-8 shrink-0 rounded-full"
              onClick={() => {
                toggleFavorite(track.id);
                toast({
                  description: favorites.includes(track.id)
                    ? "Removed from Favorites"
                    : "Added to Favorites",
                });
              }}
              aria-label={
                favorites.includes(track.id) ? "Remove from favorites" : "Add to favorites"
              }
            >
              <Heart
                className={cn(
                  "h-4 w-4",
                  favorites.includes(track.id) && "fill-primary text-primary",
                )}
              />
            </Button>
          </div>

          {/* progress */}
          <div className="mt-2 shrink-0">
            <Slider
              value={[Math.min(position, track.duration)]}
              min={0}
              max={track.duration}
              step={1}
              onValueChange={(v) => seek(v[0] ?? 0)}
              aria-label="Seek"
            />
            <div className="mt-1 flex justify-between text-[10px] tabular-nums text-muted-foreground">
              <span>{fmtTime(position)}</span>
              <span>-{fmtTime(Math.max(0, track.duration - position))}</span>
            </div>
          </div>

          {/* controls */}
          <div className="mt-1 flex shrink-0 items-center justify-between">
            <Button
              variant="ghost"
              size="icon"
              className={cn("h-8 w-8 rounded-full", shuffle && "text-primary")}
              onClick={toggleShuffle}
              aria-label="Shuffle"
            >
              <Shuffle className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className="h-9 w-9 rounded-full"
              onClick={() => prev()}
              aria-label="Previous track"
            >
              <SkipBack className="h-5 w-5 fill-current" />
            </Button>
            <button
              onClick={togglePlay}
              className="flex h-11 w-11 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition hover:scale-105 hover:bg-wav-accent-hover active:scale-95"
              aria-label={isPlaying ? "Pause" : "Play"}
            >
              {isPlaying ? (
                <Pause className="h-5 w-5 fill-primary-foreground" />
              ) : (
                <Play className="ml-0.5 h-5 w-5 fill-primary-foreground" />
              )}
            </button>
            <Button
              variant="ghost"
              size="icon"
              className="h-9 w-9 rounded-full"
              onClick={() => next()}
              aria-label="Next track"
            >
              <SkipForward className="h-5 w-5 fill-current" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className={cn("h-8 w-8 rounded-full", repeat !== "off" && "text-primary")}
              onClick={cycleRepeat}
              aria-label={`Repeat: ${repeat}`}
            >
              {repeat === "one" ? <Repeat1 className="h-4 w-4" /> : <Repeat className="h-4 w-4" />}
            </Button>
          </div>

          {/* function row */}
          <div className="mt-2.5 flex shrink-0 items-center justify-between rounded-xl bg-black/25 px-1.5 py-1">
            {fnRow.map((f) => (
              <button
                key={f.label}
                onClick={f.onClick}
                className={cn(
                  "flex min-w-11 flex-col items-center gap-0.5 rounded-lg px-1 py-1 text-[9px] font-medium transition-colors hover:text-foreground",
                  f.active ? "text-primary" : "text-muted-foreground",
                )}
                aria-label={f.label}
              >
                <f.icon className="h-4 w-4" />
                <span className="max-w-12 truncate">{f.label}</span>
              </button>
            ))}
          </div>

          {/* queue position */}
          <div className="mt-2 flex shrink-0 items-center justify-center gap-2 text-[10px] text-muted-foreground">
            {isPlaying && <EqBars className="h-2.5" />}
            <span>
              {queue ? `${queue.trackIds.indexOf(track.id) + 1} of ${queue.trackIds.length}` : ""}
            </span>
          </div>
        </div>
      )}
    </motion.aside>
  );
}
