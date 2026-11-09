"use client";

import { Cloud, Layers, Smartphone, WifiOff } from "lucide-react";
import { useWavely, useEffectiveMode } from "@/lib/wavely/store";
import type { SourceMode } from "@/lib/wavely/types";
import { cn } from "@/lib/utils";

const CHIPS: { id: SourceMode; label: string; icon: React.ElementType }[] = [
  { id: "all", label: "All", icon: Layers },
  { id: "local", label: "Local", icon: Smartphone },
  { id: "online", label: "Online", icon: Cloud },
];

/**
 * Global source switcher — the "All / Local / Online" pill row.
 * Tapping Online while offline is blocked (with a notice) because there
 * is no connection; offline locks the whole app to the local side.
 */
export function SourceModeChips({ className }: { className?: string }) {
  const mode = useEffectiveMode();
  const setSourceMode = useWavely((s) => s.setSourceMode);
  const isOffline = useWavely((s) => s.isOffline);

  return (
    <div
      className={cn("no-scrollbar flex items-center gap-2 overflow-x-auto", className)}
      role="tablist"
      aria-label="Music source"
    >
      {isOffline && (
        <span
          className="flex h-9 shrink-0 items-center gap-1.5 rounded-full bg-amber-500/15 px-3 text-xs font-semibold text-amber-400"
          title="No connection — on-device music only"
        >
          <WifiOff className="h-3.5 w-3.5" />
          Offline
        </span>
      )}
      {CHIPS.map((c) => {
        const Icon = c.icon;
        const active = mode === c.id;
        return (
          <button
            key={c.id}
            role="tab"
            aria-selected={active}
            onClick={() => setSourceMode(c.id)}
            className={cn(
              "flex h-9 shrink-0 items-center gap-1.5 rounded-full px-4 text-sm font-semibold transition-all",
              active
                ? "bg-primary text-primary-foreground shadow-md shadow-primary/25"
                : "border border-border bg-secondary/80 text-muted-foreground hover:text-foreground",
            )}
          >
            <Icon className="h-3.5 w-3.5" />
            {c.label}
          </button>
        );
      })}
    </div>
  );
}

/** Slim amber banner explaining the offline state (auto local-only). */
export function OfflineBanner() {
  const isOffline = useWavely((s) => s.isOffline);
  if (!isOffline) return null;
  return (
    <div className="flex items-center gap-2.5 rounded-xl bg-amber-500/10 px-3.5 py-2.5 text-[13px] text-amber-300/90">
      <WifiOff className="h-4 w-4 shrink-0" />
      <p>
        You&apos;re offline — Wavely switched to <b>offline player</b> mode. Only on-device and
        downloaded songs are shown, and online badges are hidden.
      </p>
    </div>
  );
}
