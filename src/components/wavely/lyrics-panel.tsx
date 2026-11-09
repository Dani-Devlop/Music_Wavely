"use client";

import { useEffect, useMemo, useRef } from "react";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import { Mic2, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export function LyricsPanel() {
  const track = useCurrentTrack();
  const position = useWavely((s) => s.position);
  const seek = useWavely((s) => s.seek);
  const containerRef = useRef<HTMLDivElement>(null);

  const activeIndex = useMemo(() => {
    if (!track?.lyrics?.length) return -1;
    let idx = -1;
    for (let i = 0; i < track.lyrics.length; i++) {
      if (track.lyrics[i].time <= position) idx = i;
      else break;
    }
    return idx;
  }, [track, position]);

  // auto-scroll active line into view
  useEffect(() => {
    const el = containerRef.current?.querySelector<HTMLElement>(`[data-line="${activeIndex}"]`);
    el?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, [activeIndex]);

  if (!track?.lyrics?.length) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-4 p-8 text-center">
        <div className="flex h-16 w-16 items-center justify-center rounded-full bg-accent">
          <Mic2 className="h-7 w-7 text-muted-foreground" />
        </div>
        <div>
          <p className="font-medium">No lyrics found</p>
          <p className="mt-1 max-w-xs text-sm text-muted-foreground">
            Wavely checks embedded tags first, then .lrc files, then LRCLIB online.
          </p>
        </div>
        <Button variant="outline" className="gap-2 rounded-full">
          <Search className="h-4 w-4" /> Search on LRCLIB
        </Button>
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      className="wavely-scroll h-full min-h-0 overflow-y-auto overscroll-contain scroll-smooth px-5 py-10 md:px-8"
    >
      <div className="mx-auto max-w-xl space-y-3 md:space-y-4">
        {track.lyrics.map((line, i) => (
          <button
            key={i}
            data-line={i}
            onClick={() => seek(line.time)}
            className={cn(
              "block w-full break-words text-left font-display font-bold leading-snug transition-all duration-300",
              i === activeIndex
                ? "text-xl text-primary md:text-3xl"
                : i < activeIndex
                  ? "text-base text-foreground/45 md:text-xl"
                  : "text-base text-foreground/28 md:text-xl",
            )}
            aria-current={i === activeIndex ? "true" : undefined}
          >
            {line.text}
          </button>
        ))}
        <p className="pb-2 pt-4 text-center text-xs text-muted-foreground">
          Tap a line to jump • synced via embedded tags
        </p>
      </div>
    </div>
  );
}
