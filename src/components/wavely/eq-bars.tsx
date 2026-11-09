"use client";

import { cn } from "@/lib/utils";

/** Three animated bars — the "now playing" indicator. */
export function EqBars({
  className,
  barClassName = "bg-primary",
}: {
  className?: string;
  barClassName?: string;
}) {
  return (
    <div className={cn("eq-bar-anim flex h-4 items-end gap-[2px]", className)} aria-hidden="true">
      <span className={cn("w-[3px] rounded-full", barClassName)} style={{ height: "100%" }} />
      <span className={cn("w-[3px] rounded-full", barClassName)} style={{ height: "100%" }} />
      <span className={cn("w-[3px] rounded-full", barClassName)} style={{ height: "100%" }} />
    </div>
  );
}
