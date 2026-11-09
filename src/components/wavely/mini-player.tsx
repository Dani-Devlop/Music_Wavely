"use client";

import Image from "next/image";
import { motion } from "framer-motion";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import { albumCover } from "@/lib/wavely/data";
import { EqBars } from "./eq-bars";
import { Slider } from "@/components/ui/slider";
import { Pause, Play, SkipForward } from "lucide-react";
import { cn } from "@/lib/utils";

/** Mobile mini player — sits above the bottom nav, opens Now Playing on tap. */
export function MiniPlayer() {
  const track = useCurrentTrack();
  const isPlaying = useWavely((s) => s.isPlaying);
  const togglePlay = useWavely((s) => s.togglePlay);
  const next = useWavely((s) => s.next);
  const position = useWavely((s) => s.position);
  const setNowPlayingOpen = useWavely((s) => s.setNowPlayingOpen);
  const nowPlayingOpen = useWavely((s) => s.nowPlayingOpen);

  if (!track || nowPlayingOpen) return null;

  const progress = Math.min(100, (position / track.duration) * 100);

  return (
    <motion.div
      initial={{ y: 80, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      exit={{ y: 80, opacity: 0 }}
      transition={{ type: "spring", damping: 30, stiffness: 300 }}
      className="fixed inset-x-2 z-30"
      style={{ bottom: "calc(env(safe-area-inset-bottom) + 4.25rem)" }}
    >
      <div className="glass overflow-hidden rounded-xl">
        {/* progress line */}
        <Slider
          value={[progress]}
          min={0}
          max={100}
          step={0.5}
          onValueChange={() => {/* visual only on mini player */}}
          className="pointer-events-none h-1 w-full [&_[data-slot=slider-range]]:bg-primary [&_[data-slot=slider-track]]:h-1 [&_[data-slot=slider-thumb]]:hidden"
          aria-label={`Progress: ${Math.round(progress)}%`}
        />
        <div className="flex items-center gap-3 p-2 pr-3">
          <button
            onClick={() => setNowPlayingOpen(true)}
            className="flex min-w-0 flex-1 items-center gap-3 text-left"
            aria-label="Open now playing"
          >
            <div className="relative h-11 w-11 shrink-0 overflow-hidden rounded-lg">
              <Image src={albumCover(track.albumId)} alt="" fill sizes="44px" className="object-cover" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold">{track.title}</p>
              <p className="truncate text-xs text-muted-foreground">{track.artist}</p>
            </div>
            {isPlaying && <EqBars className="mr-1 hidden xs:flex" />}
          </button>
          <button
            onClick={togglePlay}
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-foreground transition hover:bg-accent active:scale-95"
            aria-label={isPlaying ? "Pause" : "Play"}
          >
            {isPlaying ? <Pause className="h-6 w-6 fill-current" /> : <Play className="h-6 w-6 fill-current" />}
          </button>
          <button
            onClick={() => next()}
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-foreground transition hover:bg-accent active:scale-95"
            aria-label="Next track"
          >
            <SkipForward className="h-6 w-6 fill-current" />
          </button>
        </div>
      </div>
    </motion.div>
  );
}
