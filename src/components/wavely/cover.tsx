"use client";

import Image from "next/image";
import { useState } from "react";
import { Music2 } from "lucide-react";
import { cn } from "@/lib/utils";

const FALLBACK_HUES = [
  "from-emerald-800 to-zinc-900",
  "from-teal-800 to-zinc-900",
  "from-lime-900 to-zinc-900",
  "from-green-900 to-zinc-900",
  "from-emerald-700 to-zinc-950",
  "from-teal-700 to-zinc-950",
  "from-lime-800 to-zinc-950",
  "from-green-800 to-zinc-950",
];

/**
 * Album artwork with graceful fallback: if the image is missing (covers
 * still generating / offline), renders a green-tinted gradient tile with
 * a music glyph instead of a broken image.
 */
export function Cover({
  src,
  alt,
  size = 48,
  rounded = "rounded-md",
  className,
  priority = false,
}: {
  src: string;
  alt: string;
  size?: number;
  rounded?: string;
  className?: string;
  priority?: boolean;
}) {
  const [failed, setFailed] = useState(false);
  const hue = FALLBACK_HUES[(src.length * 7) % FALLBACK_HUES.length];

  return (
    <div
      className={cn(
        "relative shrink-0 overflow-hidden bg-secondary",
        rounded,
        className,
      )}
      style={{ width: size, height: size }}
    >
      {failed ? (
        <div
          className={cn(
            "flex h-full w-full items-center justify-center bg-gradient-to-br text-white/40",
            hue,
          )}
          aria-label={alt}
          role="img"
        >
          <Music2 style={{ width: size * 0.42, height: size * 0.42 }} />
        </div>
      ) : (
        <Image
          src={src}
          alt={alt}
          width={size}
          height={size}
          onError={() => setFailed(true)}
          priority={priority}
          className="h-full w-full object-cover"
          sizes={`${size}px`}
        />
      )}
    </div>
  );
}
