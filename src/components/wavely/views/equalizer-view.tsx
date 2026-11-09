"use client";

import { useMemo } from "react";
import { useWavely, EQ_FREQS, EQ_PRESETS } from "@/lib/wavely/store";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Slider } from "@/components/ui/slider";
import { AudioWaveform, RotateCcw, Volume2 } from "lucide-react";
import { cn } from "@/lib/utils";

function fmtFreq(hz: number): string {
  return hz >= 1000 ? `${hz / 1000}k` : `${hz}`;
}

/** SVG curve through the 10 band gains. */
function EqCurve({ bands }: { bands: number[] }) {
  const path = useMemo(() => {
    const w = 300;
    const h = 80;
    const pts = bands.map((g, i) => {
      const x = (i / (bands.length - 1)) * w;
      const y = h / 2 - (g / 12) * (h / 2 - 6);
      return [x, y] as const;
    });
    // smooth through points (simple catmull-rom → bezier)
    let d = `M ${pts[0][0]},${pts[0][1]}`;
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[Math.max(0, i - 1)];
      const p1 = pts[i];
      const p2 = pts[i + 1];
      const p3 = pts[Math.min(pts.length - 1, i + 2)];
      const c1x = p1[0] + (p2[0] - p0[0]) / 6;
      const c1y = p1[1] + (p2[1] - p0[1]) / 6;
      const c2x = p2[0] - (p3[0] - p1[0]) / 6;
      const c2y = p2[1] - (p3[1] - p1[1]) / 6;
      d += ` C ${c1x.toFixed(1)},${c1y.toFixed(1)} ${c2x.toFixed(1)},${c2y.toFixed(1)} ${p2[0].toFixed(1)},${p2[1].toFixed(1)}`;
    }
    return d;
  }, [bands]);

  return (
    <svg viewBox="0 0 300 80" className="h-20 w-full" aria-hidden="true">
      <defs>
        <linearGradient id="eq-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#1ed760" stopOpacity="0.35" />
          <stop offset="100%" stopColor="#1ed760" stopOpacity="0" />
        </linearGradient>
      </defs>
      <line x1="0" y1="40" x2="300" y2="40" stroke="currentColor" strokeOpacity="0.15" strokeDasharray="3 4" />
      <path d={`${path} L 300,80 L 0,80 Z`} fill="url(#eq-fill)" stroke="none" />
      <path d={path} fill="none" stroke="#1ed760" strokeWidth="2.5" strokeLinecap="round" />
    </svg>
  );
}

export function EqualizerView({ embedded = false }: { embedded?: boolean }) {
  const eqEnabled = useWavely((s) => s.eqEnabled);
  const setEqEnabled = useWavely((s) => s.setEqEnabled);
  const eqBands = useWavely((s) => s.eqBands);
  const setEqBand = useWavely((s) => s.setEqBand);
  const eqPreset = useWavely((s) => s.eqPreset);
  const applyEqPreset = useWavely((s) => s.applyEqPreset);
  const preamp = useWavely((s) => s.preamp);
  const setPreamp = useWavely((s) => s.setPreamp);

  return (
    <div className={cn("mx-auto max-w-3xl space-y-6 px-4 md:px-6", !embedded && "pb-8 pt-6")}>
      {!embedded && (
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/15 text-primary">
            <AudioWaveform className="h-5 w-5" />
          </div>
          <div>
            <h1 className="font-display text-2xl font-bold tracking-tight">Equalizer</h1>
            <p className="text-xs text-muted-foreground">10-band • Hi-Res pipeline</p>
          </div>
        </div>
      )}

      {/* Enable + preset */}
      <div className="flex items-center justify-between rounded-2xl bg-wav-surface p-4">
        <label className="flex items-center gap-3 text-sm font-medium" htmlFor="eq-enable">
          <Switch id="eq-enable" checked={eqEnabled} onCheckedChange={setEqEnabled} />
          {eqEnabled ? "Equalizer on" : "Equalizer off"}
        </label>
        <div className="flex items-center gap-2">
          <Select value={eqPreset} onValueChange={applyEqPreset} disabled={!eqEnabled}>
            <SelectTrigger className="w-36 rounded-full bg-secondary text-sm" aria-label="EQ preset">
              <SelectValue placeholder="Preset" />
            </SelectTrigger>
            <SelectContent className="rounded-xl">
              {Object.keys(EQ_PRESETS).map((name) => (
                <SelectItem key={name} value={name}>
                  {name}
                </SelectItem>
              ))}
              {eqPreset === "Custom" && <SelectItem value="Custom">Custom</SelectItem>}
            </SelectContent>
          </Select>
          <Button
            variant="ghost"
            size="icon"
            className="rounded-full"
            disabled={!eqEnabled}
            onClick={() => applyEqPreset("Flat")}
            aria-label="Reset equalizer"
          >
            <RotateCcw className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Curve */}
      <div className={cn("rounded-2xl bg-wav-surface p-4 text-foreground transition-opacity", !eqEnabled && "opacity-40")}>
        <EqCurve bands={eqBands} />
      </div>

      {/* Bands */}
      <div className={cn("rounded-2xl bg-wav-surface p-4 transition-opacity", !eqEnabled && "pointer-events-none opacity-40")}>
        <div className="flex items-start justify-between gap-1 sm:gap-2">
          {EQ_FREQS.map((f, i) => (
            <div key={f} className="flex flex-1 flex-col items-center gap-2">
              <span className="text-[10px] font-medium tabular-nums text-muted-foreground">
                {eqBands[i] > 0 ? `+${eqBands[i]}` : eqBands[i]}
              </span>
              <Slider
                orientation="vertical"
                value={[eqBands[i]]}
                min={-12}
                max={12}
                step={1}
                onValueChange={(v) => setEqBand(i, v[0] ?? 0)}
                className="h-36"
                aria-label={`${fmtFreq(f)} Hz band`}
              />
              <span className="text-[10px] font-semibold text-muted-foreground">{fmtFreq(f)}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Preamp */}
      <div className={cn("rounded-2xl bg-wav-surface p-4 transition-opacity", !eqEnabled && "pointer-events-none opacity-40")}>
        <div className="mb-3 flex items-center justify-between">
          <label className="flex items-center gap-2 text-sm font-medium">
            <Volume2 className="h-4 w-4 text-primary" /> Preamp
          </label>
          <span className="text-sm tabular-nums text-muted-foreground">
            {preamp > 0 ? `+${preamp}` : preamp} dB
          </span>
        </div>
        <Slider
          value={[preamp]}
          min={-15}
          max={15}
          step={1}
          onValueChange={(v) => setPreamp(v[0] ?? 0)}
          aria-label="Preamp gain"
        />
      </div>

      <p className="px-1 text-xs text-muted-foreground">
        Preset curve is applied live in the prototype. In the Flutter app this maps to the ExoPlayer / media_kit 10-band pipeline with per-device profiles.
      </p>
    </div>
  );
}
