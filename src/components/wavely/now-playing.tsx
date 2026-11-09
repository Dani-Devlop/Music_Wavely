"use client";

import Image from "next/image";
import { useState } from "react";
import { motion } from "framer-motion";
import { useWavely, useCurrentTrack, useActiveQueue } from "@/lib/wavely/store";
import { albumCover, fmtTime } from "@/lib/wavely/data";
import { LyricsPanel } from "./lyrics-panel";
import { EqBars } from "./eq-bars";
import { SleepTimerDialog } from "./sleep-timer";
import { Button } from "@/components/ui/button";
import { Slider } from "@/components/ui/slider";
import { useToast } from "@/hooks/use-toast";
import {
  ChevronDown,
  Gauge,
  Heart,
  ListMusic,
  Mic2,
  MoreVertical,
  Moon,
  Pause,
  Play,
  Repeat,
  Repeat1,
  Shuffle,
  SkipBack,
  SkipForward,
  SlidersHorizontal,
} from "lucide-react";
import { cn } from "@/lib/utils";

export function NowPlaying() {
  const open = useWavely((s) => s.nowPlayingOpen);
  const setOpen = useWavely((s) => s.setNowPlayingOpen);
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

  if (!open || !track) return null;

  const isFav = favorites.includes(track.id);
  const RepeatIcon = repeat === "one" ? Repeat1 : Repeat;

  const fnRow = [
    {
      icon: Mic2,
      label: "Lyrics",
      active: showLyrics,
      onClick: () => setShowLyrics((v) => !v),
    },
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
      label: "Sleep timer",
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
    <motion.div
      initial={{ y: "100%" }}
      animate={{ y: 0 }}
      exit={{ y: "100%" }}
      transition={{ type: "spring", damping: 32, stiffness: 320 }}
      className="fixed inset-0 z-50 overflow-hidden bg-background"
      role="dialog"
      aria-label="Now playing"
    >
      {/* blurred cover background */}
      <div className="absolute inset-0" aria-hidden="true">
        <Image
          src={albumCover(track.albumId)}
          alt=""
          fill
          sizes="100vw"
          className="scale-125 object-cover opacity-35 blur-3xl"
          priority
        />
        <div className="absolute inset-0 bg-gradient-to-b from-background/40 via-background/75 to-background" />
      </div>

      <div className="relative flex h-full flex-col">
        {/* top bar */}
        <header className="flex items-center gap-3 px-4 pt-4 md:px-6">
          <Button
            variant="ghost"
            size="icon"
            className="rounded-full"
            onClick={() => setOpen(false)}
            aria-label="Close now playing"
          >
            <ChevronDown className="h-6 w-6" />
          </Button>
          <div className="min-w-0 flex-1 text-center">
            <p className="text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">Playing from</p>
            <p className="truncate text-sm font-semibold">{queue?.name ?? "Main Queue"}</p>
          </div>
          <Button
            variant="ghost"
            size="icon"
            className="rounded-full"
            onClick={() => toast({ description: "Track menu — tag editor, ringtone cutter in the full app" })}
            aria-label="Track options"
          >
            <MoreVertical className="h-5 w-5" />
          </Button>
        </header>

        {/* cover / lyrics */}
        <div className="relative mx-auto flex min-h-0 w-full max-w-md flex-1 flex-col px-6 md:max-w-lg">
          {showLyrics ? (
            <div className="-mx-6 mt-2 flex-1 md:-mx-10">
              <LyricsPanel />
            </div>
          ) : (
            <div className="flex flex-1 items-center justify-center py-4">
              <motion.div
                key={track.id}
                initial={{ opacity: 0, scale: 0.94 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ duration: 0.35, ease: "easeOut" }}
                className="relative aspect-square w-full overflow-hidden rounded-2xl cover-shadow"
                style={{ maxWidth: "min(100%, 380px)" }}
              >
                <Image
                  src={albumCover(track.albumId)}
                  alt={`${track.album} cover art`}
                  fill
                  sizes="(max-width: 768px) 90vw, 380px"
                  className="object-cover"
                  priority
                />
              </motion.div>
            </div>
          )}
        </div>

        {/* info + controls */}
        <div className="mx-auto w-full max-w-md px-6 pb-[max(1.25rem,env(safe-area-inset-bottom))] md:max-w-lg md:px-8">
          <div className="mt-2 flex items-center gap-3">
            <div className="min-w-0 flex-1">
              <h1 className="truncate font-display text-2xl font-bold tracking-tight">{track.title}</h1>
              <p className="truncate text-sm text-muted-foreground">
                {track.artist} • {track.album}
              </p>
            </div>
            <Button
              variant="ghost"
              size="icon"
              className="rounded-full"
              onClick={() => {
                toggleFavorite(track.id);
                toast({ description: isFav ? "Removed from Favorites" : "Added to Favorites" });
              }}
              aria-label={isFav ? "Remove from favorites" : "Add to favorites"}
            >
              <Heart className={cn("h-6 w-6", isFav && "fill-primary text-primary")} />
            </Button>
          </div>

          {/* progress */}
          <div className="mt-4">
            <Slider
              value={[Math.min(position, track.duration)]}
              min={0}
              max={track.duration}
              step={1}
              onValueChange={(v) => seek(v[0] ?? 0)}
              aria-label="Seek"
            />
            <div className="mt-1.5 flex justify-between text-xs tabular-nums text-muted-foreground">
              <span>{fmtTime(position)}</span>
              <span>-{fmtTime(Math.max(0, track.duration - position))}</span>
            </div>
          </div>

          {/* main controls */}
          <div className="mt-3 flex items-center justify-between">
            <Button
              variant="ghost"
              size="icon"
              className={cn("rounded-full", shuffle && "text-primary")}
              onClick={toggleShuffle}
              aria-label="Shuffle"
            >
              <Shuffle className="h-5 w-5" />
            </Button>
            <Button variant="ghost" size="icon" className="rounded-full" onClick={() => prev()} aria-label="Previous track">
              <SkipBack className="h-7 w-7 fill-current" />
            </Button>
            <button
              onClick={togglePlay}
              className="flex h-16 w-16 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-xl transition hover:scale-[1.04] hover:bg-wav-accent-hover active:scale-95"
              aria-label={isPlaying ? "Pause" : "Play"}
            >
              {isPlaying ? (
                <Pause className="h-8 w-8 fill-primary-foreground" />
              ) : (
                <Play className="ml-1 h-8 w-8 fill-primary-foreground" />
              )}
            </button>
            <Button variant="ghost" size="icon" className="rounded-full" onClick={() => next()} aria-label="Next track">
              <SkipForward className="h-7 w-7 fill-current" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className={cn("rounded-full", repeat !== "off" && "text-primary")}
              onClick={cycleRepeat}
              aria-label={`Repeat: ${repeat}`}
            >
              <RepeatIcon className="h-5 w-5" />
            </Button>
          </div>

          {/* function row — Musicolet goodies */}
          <div className="mt-4 flex items-center justify-between rounded-2xl bg-black/25 px-3 py-2 backdrop-blur-sm">
            {fnRow.map((f) => (
              <button
                key={f.label}
                onClick={f.onClick}
                className={cn(
                  "flex min-w-14 flex-col items-center gap-1 rounded-xl px-2 py-1.5 text-[10px] font-medium transition-colors hover:text-foreground",
                  f.active ? "text-primary" : "text-muted-foreground",
                )}
              >
                <f.icon className="h-5 w-5" />
                <span className="max-w-16 truncate">{f.label}</span>
              </button>
            ))}
          </div>

          {/* current position in queue */}
          <div className="mt-2.5 flex items-center justify-center gap-2 text-[11px] text-muted-foreground">
            {isPlaying && <EqBars className="h-3" />}
            <span>
              {queue ? `${Math.max(0, indexOfCurrent(queue, track.id)) + 1} of ${queue.trackIds.length}` : ""}
            </span>
          </div>
        </div>
      </div>

      <SleepTimerDialog />
    </motion.div>
  );
}

function indexOfCurrent(queue: { trackIds: string[] }, trackId: string): number {
  return queue.trackIds.indexOf(trackId);
}
