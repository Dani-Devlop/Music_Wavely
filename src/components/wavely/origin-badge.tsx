"use client";

import { Cloud, CloudCheck } from "lucide-react";
import { SOURCE_LABELS, type Track } from "@/lib/wavely/types";
import { cn } from "@/lib/utils";

/**
 * Origin badge shown next to song titles in playlists, queues and search.
 * Kept deliberately minimal — it only answers "is this still streaming?":
 *   local file         → nothing (clean row, Musicolet style)
 *   saved / downloaded → nothing either (it IS a local file now — no "Saved" badge)
 *   online stream      → ☁ Online            (plays with internet)
 *   fully cached       → ☁✓ Cached           (heard once, plays offline too)
 * Provider names stay in the tooltip only, never in the UI.
 */
export function OriginBadge({
  track,
  cached = false,
  compact = false,
  className,
}: {
  track: Pick<Track, "origin" | "source" | "downloaded" | "quality">;
  /** track is fully cached by streaming → playable offline */
  cached?: boolean;
  /** compact → icon only (for tight rows) */
  compact?: boolean;
  className?: string;
}) {
  // local files and saved songs are just files — no badge at all
  if (track.origin === "local" || track.downloaded) return null;

  if (cached) {
    return (
      <span
        title={`Fully cached from ${track.source ? SOURCE_LABELS[track.source] : "online"} — plays offline, can be saved instantly`}
        className={cn(
          "inline-flex shrink-0 items-center gap-0.5 rounded-full bg-emerald-400/12 px-1.5 py-[1px] text-[9px] font-bold uppercase tracking-wide text-emerald-300",
          className,
        )}
      >
        <CloudCheck className="h-2.5 w-2.5" />
        Cached
      </span>
    );
  }

  return (
    <span
      title={`Streaming from ${track.source ? SOURCE_LABELS[track.source] : "online"}${track.quality ? ` • ${track.quality}kbps` : ""}`}
      className={cn(
        "inline-flex shrink-0 items-center gap-0.5 rounded-full bg-sky-400/12 px-1.5 py-[1px] text-[9px] font-bold uppercase tracking-wide text-sky-300",
        className,
      )}
    >
      <Cloud className="h-2.5 w-2.5" />
      Online
    </span>
  );
}
