"use client";

import Image from "next/image";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import { albumCover, fmtTime } from "@/lib/wavely/data";
import { EqBars } from "./eq-bars";
import { Slider } from "@/components/ui/slider";
import { Button } from "@/components/ui/button";
import {
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
  Volume2,
} from "lucide-react";
import { cn } from "@/lib/utils";

export function PlayerBar() {
  const track = useCurrentTrack();
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
  const volume = useWavely((s) => s.volume);
  const setVolume = useWavely((s) => s.setVolume);
  const favorites = useWavely((s) => s.favorites);
  const toggleFavorite = useWavely((s) => s.toggleFavorite);
  const setNowPlayingOpen = useWavely((s) => s.setNowPlayingOpen);
  const setQueueSheetOpen = useWavely((s) => s.setQueueSheetOpen);
  const setEqOpen = useWavely((s) => s.setEqOpen);
  const setSleepTimerOpen = useWavely((s) => s.setSleepTimerOpen);
  const sleepEndsAt = useWavely((s) => s.sleepEndsAt);

  if (!track) return null;
  const isFav = favorites.includes(track.id);
  const RepeatIcon = repeat === "one" ? Repeat1 : Repeat;

  return (
    <footer className="z-30 border-t border-border/70 bg-transparent">
      <div className="grid grid-cols-[1fr_auto] items-center gap-4 px-4 py-3 md:grid-cols-[minmax(180px,1fr)_minmax(320px,2fr)_minmax(180px,1fr)] md:px-6">
        {/* track info */}
        <div
          role="button"
          tabIndex={0}
          onClick={() => setNowPlayingOpen(true)}
          onKeyDown={(e) => e.key === "Enter" && setNowPlayingOpen(true)}
          className="flex min-w-0 cursor-pointer items-center gap-3 text-left"
          aria-label="Open now playing"
        >
          <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-md">
            <Image src={albumCover(track.albumId)} alt="" fill sizes="48px" className="object-cover" />
          </div>
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold">{track.title}</p>
            <p className="truncate text-xs text-muted-foreground">{track.artist}</p>
          </div>
          <button
            onClick={(e) => {
              e.stopPropagation();
              toggleFavorite(track.id);
            }}
            className="ml-1 hidden shrink-0 lg:block"
            aria-label={isFav ? "Remove from favorites" : "Add to favorites"}
          >
            <Heart className={cn("h-4 w-4 transition", isFav ? "fill-primary text-primary" : "text-muted-foreground hover:text-foreground")} />
          </button>
        </div>

        {/* center controls */}
        <div className="flex w-full flex-col items-center gap-1.5">
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="icon"
              className={cn("h-8 w-8 rounded-full", shuffle && "text-primary")}
              onClick={toggleShuffle}
              aria-label="Shuffle"
            >
              <Shuffle className="h-4 w-4" />
            </Button>
            <Button variant="ghost" size="icon" className="h-9 w-9 rounded-full" onClick={() => prev()} aria-label="Previous">
              <SkipBack className="h-5 w-5 fill-current" />
            </Button>
            <button
              onClick={togglePlay}
              className="flex h-10 w-10 items-center justify-center rounded-full bg-foreground text-background transition hover:scale-105 active:scale-95"
              aria-label={isPlaying ? "Pause" : "Play"}
            >
              {isPlaying ? <Pause className="h-5 w-5 fill-background" /> : <Play className="ml-0.5 h-5 w-5 fill-background" />}
            </button>
            <Button variant="ghost" size="icon" className="h-9 w-9 rounded-full" onClick={() => next()} aria-label="Next">
              <SkipForward className="h-5 w-5 fill-current" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className={cn("h-8 w-8 rounded-full", repeat !== "off" && "text-primary")}
              onClick={cycleRepeat}
              aria-label={`Repeat ${repeat}`}
            >
              <RepeatIcon className="h-4 w-4" />
            </Button>
          </div>
          <div className="flex w-full items-center gap-2">
            <span className="w-10 text-right text-[11px] tabular-nums text-muted-foreground">{fmtTime(position)}</span>
            <Slider
              value={[Math.min(position, track.duration)]}
              min={0}
              max={track.duration}
              step={1}
              onValueChange={(v) => seek(v[0] ?? 0)}
              className="flex-1"
              aria-label="Seek"
            />
            <span className="w-10 text-[11px] tabular-nums text-muted-foreground">-{fmtTime(Math.max(0, track.duration - position))}</span>
          </div>
        </div>

        {/* right: function icons */}
        <div className="hidden items-center justify-end gap-0.5 md:flex">
          <Button variant="ghost" size="icon" className="h-8 w-8 rounded-full" onClick={() => setNowPlayingOpen(true)} aria-label="Lyrics">
            <Mic2 className="h-4 w-4" />
          </Button>
          <Button variant="ghost" size="icon" className="h-8 w-8 rounded-full" onClick={() => setQueueSheetOpen(true)} aria-label="Queue">
            <ListMusic className="h-4 w-4" />
          </Button>
          <Button variant="ghost" size="icon" className={cn("h-8 w-8 rounded-full", sleepEndsAt && "text-primary")} onClick={() => setSleepTimerOpen(true)} aria-label="Sleep timer">
            <Moon className="h-4 w-4" />
          </Button>
          <Button variant="ghost" size="icon" className="h-8 w-8 rounded-full" onClick={() => setEqOpen(true)} aria-label="Equalizer">
            <SlidersHorizontal className="h-4 w-4" />
          </Button>
          <div className="ml-1 flex items-center gap-2">
            {isPlaying && <EqBars className="h-3" />}
            <Volume2 className="h-4 w-4 text-muted-foreground" />
            <Slider
              value={[volume * 100]}
              min={0}
              max={100}
              step={1}
              onValueChange={(v) => setVolume((v[0] ?? 0) / 100)}
              className="w-20"
              aria-label="Volume"
            />
          </div>
        </div>
      </div>
    </footer>
  );
}
