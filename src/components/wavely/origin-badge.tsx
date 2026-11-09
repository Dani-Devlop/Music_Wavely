"use client";

import { Check, Cloud } from "lucide-react";
import { SOURCE_LABELS, type Track } from "@/lib/wavely/types";
import { cn } from "@/lib/utils";

/**
 * Origin badge shown next to song titles in playlists, queues and search.
 *  local file      → nothing (clean row, Musicolet style)
 *  online stream   → ☁ + provider name
 *  downloaded      → ✓ Saved (behaves like a local file, badge hides offline)
 */
export function OriginBadge({
  track,
  compact = false,
  className,
}: {
  track: Pick<Track, "origin" | "source" | "downloaded" | "quality">;
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

  const label = track.source ? SOURCE_LABELS[track.source] : "Online";
  return (
    <span
      title={`Streaming from ${label}${track.quality ? ` • ${track.quality}kbps` : ""}`}
      className={cn(
        "inline-flex shrink-0 items-center gap-0.5 rounded-full bg-sky-400/12 px-1.5 py-[1px] text-[9px] font-bold uppercase tracking-wide text-sky-300",
        className,
      )}
    >
      <Cloud className="h-2.5 w-2.5" />
      {compact ? null : label}
      {!compact && track.quality ? ` • ${track.quality}` : ""}
    </span>
  );
}
