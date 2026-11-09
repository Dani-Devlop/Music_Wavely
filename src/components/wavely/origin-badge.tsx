"use client";

import { Check, Cloud, CloudCheck } from "lucide-react";
import { SOURCE_LABELS, type Track } from "@/lib/wavely/types";
import { cn } from "@/lib/utils";

/**
 * Origin badge shown next to song titles in playlists, queues and search.
 * Kept deliberately minimal — it only answers "where does this come from":
 *   local file        → nothing (clean row, Musicolet style)
 *   online stream     → ☁ Online            (plays with internet)
 *   fully cached      → ☁✓ Cached           (heard once, plays offline too)
 *   saved / downloaded → ✓ Saved            (real file in the music folder)
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
  if (track.origin === "local") return null;

  if (track.downloaded) {
    return (
      <span
        title="Saved on device — plays offline"
        className={cn(
          "inline-flex shrink-0 items-center gap-0.5 rounded-full bg-primary/15 px-1.5 py-[1px] text-[9px] font-bold uppercase tracking-wide text-primary",
          className,
        )}
      >
        <Check className="h-2.5 w-2.5" strokeWidth={3} />
        Saved{!compact && track.quality ? ` • ${track.quality}` : ""}
      </span>
    );
  }

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
