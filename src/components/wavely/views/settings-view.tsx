"use client";

import { useState } from "react";
import { useWavely, CACHE_LIMIT_MB, useCacheUsage } from "@/lib/wavely/store";
import { EqualizerView } from "./equalizer-view";
import { Button } from "@/components/ui/button";
import { Slider } from "@/components/ui/slider";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import { Input } from "@/components/ui/input";
import {
  Bell,
  ChevronRight,
  CloudDownload,
  Download,
  Folder,
  FolderDown,
  FolderSync,
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
  Trash2,
  Waves,
  WifiOff,
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

function previewTemplate(template: string, sample: { country: string; genre: string; artist: string; album: string; year: number; title: string; ext: string }) {
  const dir = template
    .replace(/\{\s*Country\s*\}/gi, sample.country)
    .replace(/\{\s*Genre\s*\}/gi, sample.genre)
    .replace(/\{\s*Artist\s*\}/gi, sample.artist)
    .replace(/\{\s*Album\s*\}/gi, sample.album)
    .replace(/\{\s*Year\s*\}/gi, String(sample.year))
    .replace(/\{\s*Title\s*\}/gi, sample.title)
    .replace(/\/+/g, "/")
    .replace(/^\/|\/$/g, "");
  return `${dir}/${sample.artist} - ${sample.title}.${sample.ext}`;
}

export function SettingsView() {
  const [page, setPage] = useState<"root" | "eq">("root");
  const { toast } = useToast();

  // downloads & storage (store-backed so the whole app sees them)
  const downloadPath = useWavely((s) => s.downloadPath);
  const setDownloadPath = useWavely((s) => s.setDownloadPath);
  const folderTemplate = useWavely((s) => s.folderTemplate);
  const setFolderTemplate = useWavely((s) => s.setFolderTemplate);
  const audioFormat = useWavely((s) => s.audioFormat);
  const setAudioFormat = useWavely((s) => s.setAudioFormat);
  const isOffline = useWavely((s) => s.isOffline);
  const setOffline = useWavely((s) => s.setOffline);
  const cachedCount = useWavely((s) => s.cachedIds.length);
  const clearCache = useWavely((s) => s.clearCache);
  const cacheUsed = useCacheUsage();

  // playback prefs (prototype-local)
  const [gapless, setGapless] = useState(true);
  const [crossfade, setCrossfade] = useState(4);
  const [replayGain, setReplayGain] = useState<"off" | "track" | "album">("track");
  const [hires, setHires] = useState(true);
  const [amoled, setAmoled] = useState(false);
  const [notif, setNotif] = useState(true);
  const [parental, setParental] = useState(false);
  const [autoDownload, setAutoDownload] = useState(false);
  const [mobileData, setMobileData] = useState(true);
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

      <SectionHeader icon={FolderDown} title="Downloads & storage" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <div className="px-3 py-3">
          <p className="mb-2 text-sm font-medium">Download location</p>
          <div className="flex gap-2">
            <Input
              value={downloadPath}
              onChange={(e) => setDownloadPath(e.target.value)}
              className="h-10 flex-1 font-mono text-xs"
              aria-label="Download path"
              spellCheck={false}
            />
            <Button
              variant="outline"
              size="icon"
              className="h-10 w-10 shrink-0"
              onClick={() => toast({ description: "SAF folder picker opens here in the Flutter app" })}
              aria-label="Choose folder"
            >
              <Folder className="h-4 w-4" />
            </Button>
          </div>
          <p className="mt-1.5 text-[11px] text-muted-foreground">
            Default: /storage/emulated/0/Music/Wavely — Musicolet can play straight from this folder.
          </p>
        </div>
        <Separator />
        <div className="px-3 py-3">
          <p className="mb-1 text-sm font-medium">Folder organisation</p>
          <p className="mb-2 text-xs text-muted-foreground">
            Build the folder structure for saved songs — your {"{Country}/{Genre}"} idea:
          </p>
          <div className="no-scrollbar mb-2 flex gap-1.5 overflow-x-auto pb-1">
            {["{Country}", "{Genre}", "{Artist}", "{Album}", "{Year}", "{Title}"].map((tok) => (
              <button
                key={tok}
                onClick={() => {
                  setFolderTemplate(folderTemplate ? `${folderTemplate}/${tok}` : tok);
                  toast({ description: `Added ${tok} to the template` });
                }}
                className="shrink-0 rounded-full bg-secondary px-3 py-1.5 font-mono text-[11px] text-muted-foreground transition hover:bg-accent hover:text-foreground"
              >
                {tok}
              </button>
            ))}
            <button
              onClick={() => setFolderTemplate("")}
              className="shrink-0 rounded-full px-2.5 py-1.5 text-[11px] text-muted-foreground transition hover:text-foreground"
            >
              Clear
            </button>
          </div>
          <div className="rounded-lg bg-secondary/60 p-2.5 font-mono text-[11px]">
            <p className="mb-1 text-muted-foreground">Preview</p>
            <p className="break-all text-primary" aria-live="polite">
              {downloadPath.replace(/\/$/, "")}/{previewTemplate(folderTemplate || "--", {
                country: "US",
                genre: "Synthpop",
                artist: "Midnight Arcade",
                album: "Chrome City",
                year: 2025,
                title: "Night Circuit",
                ext: audioFormat === "flac" ? "flac" : "mp3",
              })}
            </p>
          </div>
        </div>
        <Separator />
        <Row
          icon={Download}
          title="Audio format"
          subtitle="Quality of saved songs"
          control={
            <div className="flex overflow-hidden rounded-full bg-secondary text-xs font-medium">
              {(["mp3-320", "flac"] as const).map((f) => (
                <button
                  key={f}
                  onClick={() => setAudioFormat(f)}
                  className={cn("px-3 py-1.5 transition", audioFormat === f && "bg-primary text-primary-foreground")}
                >
                  {f === "flac" ? "FLAC" : "MP3 320"}
                </button>
              ))}
            </div>
          }
        />
        <Separator />
        <Row icon={WifiOff} title="Download only on Wi-Fi" subtitle="Skip downloads on mobile data" control={<Switch checked={mobileData} onCheckedChange={setMobileData} />} />
        <Separator />
        <Row icon={Download} title="Auto-download favorites" subtitle="From online sources when available" control={<Switch checked={autoDownload} onCheckedChange={setAutoDownload} />} />
        <Separator />
        <Row icon={FolderSync} title="Keep organised on move" subtitle="Re-shelve files if the template changes" control={<Switch defaultChecked />} />
      </div>

      <SectionHeader icon={CloudDownload} title="Streaming cache" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <div className="px-3 py-3">
          <div className="mb-1.5 flex items-center justify-between text-sm">
            <span className="font-medium">Cache usage</span>
            <span className="text-xs tabular-nums text-muted-foreground">
              {cacheUsed} of {CACHE_LIMIT_MB} MB
            </span>
          </div>
          <div
            className="h-2 w-full overflow-hidden rounded-full bg-secondary"
            role="progressbar"
            aria-valuenow={cacheUsed}
            aria-valuemin={0}
            aria-valuemax={CACHE_LIMIT_MB}
            aria-label="Streaming cache usage"
          >
            <div
              className="h-full rounded-full bg-primary transition-all"
              style={{ width: `${Math.min(100, (cacheUsed / CACHE_LIMIT_MB) * 100)}%` }}
            />
          </div>
          <p className="mt-1.5 text-[11px] text-muted-foreground">
            {cachedCount} fully cached — play offline &amp; save instantly, no re-download
          </p>
        </div>
        <Separator />
        <Row
          icon={CloudDownload}
          title="Hard limit: 400 MB"
          subtitle="Fits under 400 MB — when it fills, the oldest cached songs are evicted first (LRU)"
        />
        <Separator />
        <Row
          icon={Folder}
          title="No cache folder in your music"
          subtitle="The cache is invisible app storage — saved songs move OUT of the cache into your music folder"
        />
        <Separator />
        <Row
          icon={Trash2}
          title="Clear cache"
          subtitle="Frees space — cached songs go back to streaming-only"
          onClick={() => {
            clearCache();
            toast({ description: "Streaming cache cleared" });
          }}
          arrow
        />
        <Separator />
        <Row
          icon={Info}
          title="How it works"
          subtitle="Songs you stream fill the cache as you listen. Fully cached songs survive a dropped connection — half-cached ones don't, and can't be saved."
        />
      </div>

      <SectionHeader icon={WifiOff} title="Connection (prototype)" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row
          icon={WifiOff}
          title="Simulate offline mode"
          subtitle={isOffline ? "ON — app locked to on-device music" : "Preview how Wavely becomes an offline player"}
          control={<Switch checked={isOffline} onCheckedChange={setOffline} />}
        />
        <Separator />
        <Row icon={Info} title="In the real app" subtitle="Offline state is detected automatically (no connection)" />
      </div>

      <SectionHeader icon={ListMusic} title="Queues & library" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={ListMusic} title="Queue slots" subtitle="Up to 20 queues, positions saved" />
        <Separator />
        <Row icon={ScanLine} title="Scan library" subtitle="Rescan folders for new songs" onClick={() => toast({ description: "Library scan started — 34 songs found" })} arrow />
        <Separator />
        <Row icon={Folder} title="Blacklist folders" subtitle="Hide folders from the library" onClick={() => toast({ description: "Folder picker in the full app" })} arrow />
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
