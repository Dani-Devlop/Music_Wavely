"use client";

import { Cover } from "./cover";
import { EqBars } from "./eq-bars";
import { OriginBadge } from "./origin-badge";
import { useWavely, useIsTrackPlayable } from "@/lib/wavely/store";
import { albumCover, fmtTime } from "@/lib/wavely/data";
import type { Track } from "@/lib/wavely/types";
import { MoreVertical, Play } from "lucide-react";
import { cn } from "@/lib/utils";
import { useToast } from "@/hooks/use-toast";

/**
 * Clean Spotify-style row: info left, ⋯ right.
 * All actions (like, playlist, queue, share…) live in the shared
 * TrackActionsSheet — no inline heart button anymore.
 */
export function SongRow({
  track,
  index,
  onPlay,
  showIndex = false,
  compact = false,
  hideOriginChip = false,
}: {
  track: Track;
  index?: number;
  onPlay: () => void;
  showIndex?: boolean;
  compact?: boolean;
  /** S27: search results must never carry a local/online badge */
  hideOriginChip?: boolean;
}) {
  const { toast } = useToast();
  const currentTrack = useWavely((s) => s.currentTrack());
  const isPlaying = useWavely((s) => s.isPlaying);
  const isOffline = useWavely((s) => s.isOffline);
  const openActions = useWavely((s) => s.openActions);
  const setNowPlayingOpen = useWavely((s) => s.setNowPlayingOpen);
  const isCached = useWavely((s) => s.cachedIds.includes(track.id));
  const playable = useIsTrackPlayable(track);
  const isCurrent = currentTrack?.id === track.id;

  const handleUnavailable = () => {
    toast({
      description: isOffline
        ? "You're offline — download this song or go back online"
        : "This track isn't available right now",
    });
  };

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => {
        if (!playable) {
          handleUnavailable();
          return;
        }
        onPlay();
        setNowPlayingOpen(true);
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter") {
          if (!playable) {
            handleUnavailable();
            return;
          }
          onPlay();
          setNowPlayingOpen(true);
        }
      }}
      className={cn(
        "group flex w-full cursor-pointer items-center gap-3 rounded-lg px-2 py-2 text-left transition-colors hover:bg-accent/70 focus-visible:bg-accent/70 focus-visible:outline-none",
        compact && "py-1.5",
        !playable && "opacity-55",
      )}
      title={!playable ? "Unavailable offline" : undefined}
    >
      {showIndex && (
        <span className="w-6 shrink-0 text-center text-sm text-muted-foreground tabular-nums">
          {(index ?? 0) + 1}
        </span>
      )}
      <div className="relative">
        <Cover src={albumCover(track.albumId)} alt={track.album} size={compact ? 40 : 48} />
        <div
          className={cn(
            "absolute inset-0 flex items-center justify-center rounded-md bg-black/55 opacity-0 transition-opacity group-hover:opacity-100",
            isCurrent && "opacity-100",
          )}
        >
          {isCurrent && isPlaying ? (
            <EqBars />
          ) : (
            <Play className="h-5 w-5 fill-white text-white" />
          )}
        </div>
      </div>
      <div className="min-w-0 flex-1">
        <p
          className={cn(
            "flex items-center gap-1.5 truncate text-[15px] font-medium leading-tight",
            isCurrent && "text-primary",
          )}
        >
          <span className="truncate">{track.title}</span>
          {!hideOriginChip && <OriginBadge track={track} cached={isCached} compact={compact} />}
        </p>
        <p className="truncate text-[13px] leading-tight text-muted-foreground">
          {track.artist} • {track.album}
        </p>
      </div>
      <span className="w-10 shrink-0 text-right text-[13px] tabular-nums text-muted-foreground">
        {fmtTime(track.duration)}
      </span>
      <button
        onClick={(e) => {
          e.stopPropagation();
          openActions(track.id);
        }}
        aria-label={`More options for ${track.title}`}
        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
      >
        <MoreVertical className="h-4 w-4" />
      </button>
    </div>
  );
}
