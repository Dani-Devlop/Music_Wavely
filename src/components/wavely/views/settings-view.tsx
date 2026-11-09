"use client";

import { useState } from "react";
import { useWavely } from "@/lib/wavely/store";
import { EqualizerView } from "./equalizer-view";
import { Button } from "@/components/ui/button";
import { Slider } from "@/components/ui/slider";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import {
  Bell,
  ChevronRight,
  Download,
  Folder,
  Github,
  Heart,
  Info,
  ListMusic,
  Lock,
  Mic2,
  Moon,
  Palette,
  RotateCcw,
  ScanLine,
  SlidersHorizontal,
  Timer,
  Waves,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useToast } from "@/hooks/use-toast";
import type { AppView } from "@/lib/wavely/types";

function SectionHeader({ icon: Icon, title }: { icon: React.ElementType; title: string }) {
  return (
    <div className="flex items-center gap-2 pb-1 pt-5">
      <Icon className="h-4 w-4 text-primary" />
      <h2 className="text-xs font-bold uppercase tracking-widest text-primary">{title}</h2>
    </div>
  );
}

function Row({
  icon: Icon,
  title,
  subtitle,
  control,
  onClick,
  arrow,
}: {
  icon: React.ElementType;
  title: string;
  subtitle?: string;
  control?: React.ReactNode;
  onClick?: () => void;
  arrow?: boolean;
}) {
  const content = (
    <>
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-accent text-foreground">
        <Icon className="h-4 w-4" />
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium">{title}</p>
        {subtitle && <p className="truncate text-xs text-muted-foreground">{subtitle}</p>}
      </div>
      {control}
      {arrow && <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />}
    </>
  );
  const cls = "flex w-full items-center gap-3 px-3 py-3 text-left transition hover:bg-accent/50";
  return onClick ? (
    <button onClick={onClick} className={cls}>{content}</button>
  ) : (
    <div className={cls}>{content}</div>
  );
}

export function SettingsView() {
  const [page, setPage] = useState<"root" | "eq">("root");
  const { toast } = useToast();

  // playback prefs (prototype-local)
  const [gapless, setGapless] = useState(true);
  const [crossfade, setCrossfade] = useState(4);
  const [replayGain, setReplayGain] = useState<"off" | "track" | "album">("track");
  const [hires, setHires] = useState(true);
  const [amoled, setAmoled] = useState(false);
  const [notif, setNotif] = useState(true);
  const [parental, setParental] = useState(false);
  const [autoDownload, setAutoDownload] = useState(false);
  const [lyricsPriority] = useState(["Embedded (USLT/SYLT)", ".lrc sidecar file", "Web / LRCLIB"]);

  const speed = useWavely((s) => s.speed);
  const setSpeed = useWavely((s) => s.setSpeed);
  const setEqOpen = useWavely((s) => s.setEqOpen);
  const setSleepTimer = useWavely((s) => s.setSleepTimer);

  if (page === "eq") {
    return (
      <div className="mx-auto max-w-3xl px-4 pb-8 pt-6 md:px-6">
        <Button variant="ghost" size="sm" className="mb-2 gap-1 rounded-full" onClick={() => setPage("root")}>
          <ChevronRight className="h-4 w-4 rotate-180" /> Settings
        </Button>
        <EqualizerView embedded />
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl space-y-1 px-4 pb-10 pt-6 md:px-6">
      <h1 className="mb-1 font-display text-2xl font-bold tracking-tight md:text-3xl">Settings</h1>

      <SectionHeader icon={Palette} title="Appearance" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={Moon} title="Theme" subtitle="Dark (light theme coming later)" />
        <Separator />
        <Row icon={Waves} title="AMOLED black" subtitle="True black background" control={<Switch checked={amoled} onCheckedChange={setAmoled} />} />
        <Separator />
        <Row icon={Palette} title="Accent color" subtitle="Wavely green" control={<span className="h-6 w-6 rounded-full bg-primary ring-2 ring-primary/40" />} />
      </div>

      <SectionHeader icon={SlidersHorizontal} title="Playback" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={Waves} title="Gapless playback" subtitle="Seamless album transitions" control={<Switch checked={gapless} onCheckedChange={setGapless} />} />
        <Separator />
        <div className="px-3 py-3">
          <div className="mb-2 flex items-center justify-between text-sm">
            <span className="font-medium">Crossfade</span>
            <span className="text-muted-foreground">{crossfade === 0 ? "Off" : `${crossfade}s`}</span>
          </div>
          <Slider value={[crossfade]} min={0} max={12} step={1} onValueChange={(v) => setCrossfade(v[0] ?? 0)} aria-label="Crossfade seconds" />
        </div>
        <Separator />
        <Row
          icon={Waves}
          title="ReplayGain"
          subtitle="Level volume across tracks"
          control={
            <div className="flex overflow-hidden rounded-full bg-secondary text-xs font-medium">
              {(["off", "track", "album"] as const).map((m) => (
                <button
                  key={m}
                  onClick={() => setReplayGain(m)}
                  className={cn("px-3 py-1.5 capitalize transition", replayGain === m && "bg-primary text-primary-foreground")}
                >
                  {m}
                </button>
              ))}
            </div>
          }
        />
        <Separator />
        <Row icon={Timer} title="Default speed" subtitle={`${speed.toFixed(1)}× playback rate`} control={
          <div className="flex overflow-hidden rounded-full bg-secondary text-xs font-medium">
            {[0.75, 1, 1.25, 1.5].map((v) => (
              <button key={v} onClick={() => setSpeed(v)} className={cn("px-2.5 py-1.5 transition", speed === v && "bg-primary text-primary-foreground")}>
                {v}×
              </button>
            ))}
          </div>
        } />
      </div>

      <SectionHeader icon={SlidersHorizontal} title="Audio" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={SlidersHorizontal} title="Equalizer" subtitle="10-band + presets" onClick={() => setPage("eq")} arrow />
        <Separator />
        <Row icon={Waves} title="Hi-Res output" subtitle="Bit-perfect where supported" control={<Switch checked={hires} onCheckedChange={setHires} />} />
        <Separator />
        <Row icon={Timer} title="Sleep timer" subtitle="Set from Now Playing" onClick={() => { setSleepTimer(15); toast({ description: "Sleep timer: 15 min (quick set)" }); }} arrow />
      </div>

      <SectionHeader icon={Mic2} title="Lyrics" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={Mic2} title="Lyrics sources" subtitle={lyricsPriority.join("  →  ")} arrow onClick={() => toast({ description: "Drag-to-reorder sources in the full app" })} />
        <Separator />
        <Row icon={Download} title="Auto-save lyrics" subtitle="Cache web lyrics to .lrc" control={<Switch defaultChecked />} />
      </div>

      <SectionHeader icon={ListMusic} title="Queues & library" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={ListMusic} title="Queue slots" subtitle="Up to 20 queues, positions saved" />
        <Separator />
        <Row icon={ScanLine} title="Scan library" subtitle="Rescan folders for new songs" onClick={() => toast({ description: "Library scan started — 34 songs found" })} arrow />
        <Separator />
        <Row icon={Folder} title="Blacklist folders" subtitle="Hide folders from the library" onClick={() => toast({ description: "Folder picker in the full app" })} arrow />
        <Separator />
        <Row icon={Download} title="Auto-download favorites" subtitle="From online sources when available" control={<Switch checked={autoDownload} onCheckedChange={setAutoDownload} />} />
      </div>

      <SectionHeader icon={Lock} title="Parental controls" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={Lock} title="Require PIN" subtitle="Lock explicit content & settings" control={<Switch checked={parental} onCheckedChange={(v) => { setParental(v); if (v) toast({ description: "PIN setup opens in the full app" }); }} />} />
      </div>

      <SectionHeader icon={Bell} title="Notifications" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={Bell} title="Media notification" subtitle="Lock-screen controls & artwork" control={<Switch checked={notif} onCheckedChange={setNotif} />} />
      </div>

      <SectionHeader icon={Info} title="About" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={Info} title="Version" subtitle="1.0.3-prototype (design preview)" />
        <Separator />
        <Row icon={Github} title="Source code" subtitle="github.com/Dani-Devlop/Music_Wavely" onClick={() => window.open("https://github.com/Dani-Devlop/Music_Wavely", "_blank")} arrow />
        <Separator />
        <Row icon={Heart} title="Made with love" subtitle="Musicolet's soul, Spotify's style" />
      </div>

      <p className="pb-2 pt-6 text-center text-xs text-muted-foreground">
        Wavely — free & open source. Settings marked “full app” land in the Flutter build.
      </p>
    </div>
  );
}
