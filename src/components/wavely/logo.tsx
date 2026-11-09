import { cn } from "@/lib/utils";

/**
 * Wavely mark — rounded tile with a soundwave "W".
 * Fresh 2025 rebrand: gradient green tile + white equalizer bars.
 */
export function WavelyMark({
  size = 36,
  className,
}: {
  size?: number;
  className?: string;
}) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 48 48"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      aria-hidden="true"
    >
      <defs>
        <linearGradient id="wavely-tile" x1="4" y1="4" x2="44" y2="44" gradientUnits="userSpaceOnUse">
          <stop stopColor="#1ED760" />
          <stop offset="1" stopColor="#0E8C42" />
        </linearGradient>
      </defs>
      <rect x="2" y="2" width="44" height="44" rx="12" fill="url(#wavely-tile)" />
      {/* soundwave forming a subtle W */}
      <rect x="10" y="20" width="4.5" height="8" rx="2.25" fill="white" fillOpacity="0.55" />
      <rect x="17.5" y="14" width="4.5" height="20" rx="2.25" fill="white" fillOpacity="0.75" />
      <rect x="25" y="10" width="4.5" height="28" rx="2.25" fill="white" />
      <rect x="32.5" y="16" width="4.5" height="16" rx="2.25" fill="white" fillOpacity="0.75" />
      <rect x="40" y="22" width="4.5" height="4" rx="2" fill="white" fillOpacity="0.4" />
    </svg>
  );
}

export function WavelyLogo({
  size = 36,
  showWordmark = true,
  className,
}: {
  size?: number;
  showWordmark?: boolean;
  className?: string;
}) {
  return (
    <div className={cn("flex items-center gap-2.5 select-none", className)}>
      <WavelyMark size={size} />
      {showWordmark && (
        <span
          className="font-display font-bold tracking-tight text-foreground"
          style={{ fontSize: size * 0.62 }}
        >
          Wave<span className="text-primary">ly</span>
        </span>
      )}
    </div>
  );
}
