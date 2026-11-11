"use client";

import { useState } from "react";
import Image from "next/image";
import {
  useWavely,
  CACHE_LIMIT_MB,
  useCacheUsage,
  LYRICS_TARGET_LANGS,
  REGIONS,
  MUSIC_LANGUAGES,
  renderFolderTemplate,
  renderFileTemplate,
  BACKUP_AUTO_LABELS,
  DEFAULT_BACKUP_PATH,
  type BackupAuto,
} from "@/lib/wavely/store";
import { TRACKS } from "@/lib/wavely/data";
import { EqualizerView } from "./equalizer-view";
import { AccountView } from "./account-view";
import { Button } from "@/components/ui/button";
import { Slider } from "@/components/ui/slider";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Bell,
  Ban,
  ChevronRight,
  CloudDownload,
  Compass,
  Cookie,
  DatabaseBackup,
  Download,
  Folder,
  FolderDown,
  FolderPlus,
  FolderSync,
  Github,
  Heart,
  History,
  Info,
  Languages,
  ListMusic,
  Lock,
  Mic2,
  Moon,
  Palette,
  RotateCcw,
  ScanLine,
  ShieldCheck,
  Smartphone,
  SlidersHorizontal,
  Sparkles,
  Timer,
  Trash2,
  UserRound,
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

/** sample track for the storage-organisation preview (wizard uses the same idea) */
const SAMPLE_TRACK = {
  country: "US",
  genre: "Synthpop",
  artist: "Midnight Arcade",
  album: "Chrome City",
  year: 2025,
  title: "Night Circuit",
  track: 7,
};

export function SettingsView() {
  // sub-page lives in the store so the Home avatar & rows can deep-link (account page)
  const page = useWavely((s) => s.settingsPage);
  const setPage = useWavely((s) => s.setSettingsPage);
  const { toast } = useToast();

  // downloads & storage (store-backed so the whole app sees them)
  const downloadPath = useWavely((s) => s.downloadPath);
  const setDownloadPath = useWavely((s) => s.setDownloadPath);
  const folderTemplate = useWavely((s) => s.folderTemplate);
  const setFolderTemplate = useWavely((s) => s.setFolderTemplate);
  const fileTemplate = useWavely((s) => s.fileTemplate);
  const setFileTemplate = useWavely((s) => s.setFileTemplate);
  const backupEnabled = useWavely((s) => s.backupEnabled);
  const setBackupEnabled = useWavely((s) => s.setBackupEnabled);
  const backupPath = useWavely((s) => s.backupPath);
  const setBackupPath = useWavely((s) => s.setBackupPath);
  const backupAuto = useWavely((s) => s.backupAuto);
  const setBackupAuto = useWavely((s) => s.setBackupAuto);
  const downloadQuality = useWavely((s) => s.downloadQuality);
  const setDownloadQuality = useWavely((s) => s.setDownloadQuality);

  // setup wizard prefs — same store the wizard writes
  const region = useWavely((s) => s.region);
  const setRegion = useWavely((s) => s.setRegion);
  const musicLanguages = useWavely((s) => s.musicLanguages);
  const neverPlayLanguages = useWavely((s) => s.neverPlayLanguages);
  const musicFolders = useWavely((s) => s.musicFolders);
  const addMusicFolder = useWavely((s) => s.addMusicFolder);
  const removeMusicFolder = useWavely((s) => s.removeMusicFolder);
  const parentalMode = useWavely((s) => s.parentalMode);
  const setParentalMode = useWavely((s) => s.setParentalMode);
  const aiFeatures = useWavely((s) => s.aiFeatures);
  const setAiFeatures = useWavely((s) => s.setAiFeatures);

  const FOLDER_SUGGESTIONS = [
    "/storage/emulated/0/Music",
    "/storage/0000-0000/Music",
    "/storage/emulated/0/Download/Music",
    "/sdcard/Music",
  ];
  const addSuggestedFolder = () => {
    const suggestion =
      FOLDER_SUGGESTIONS.find((f) => !musicFolders.includes(f)) ??
      `/storage/emulated/0/Music/Folder-${musicFolders.length + 1}`;
    addMusicFolder(suggestion);
  };
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
  const [autoDownload, setAutoDownload] = useState(false);
  const [mobileData, setMobileData] = useState(true);
  const [lyricsPriority] = useState(["Embedded (USLT/SYLT)", ".lrc sidecar file", "Web / LRCLIB"]);

  const speed = useWavely((s) => s.speed);
  const setSpeed = useWavely((s) => s.setSpeed);
  const setEqOpen = useWavely((s) => s.setEqOpen);
  const setSleepTimer = useWavely((s) => s.setSleepTimer);

  // lyrics translation (language-agnostic — user rule #16)
  const lyricsTranslate = useWavely((s) => s.lyricsTranslate);
  const setLyricsTranslate = useWavely((s) => s.setLyricsTranslate);
  const lyricsTargetLang = useWavely((s) => s.lyricsTargetLang);
  const setLyricsTargetLang = useWavely((s) => s.setLyricsTargetLang);
  const setOnboardingOpen = useWavely((s) => s.setOnboardingOpen);

  // account & privacy — profile hero + management rows (full page = account-view)
  const profile = useWavely((s) => s.profile);
  const sessions = useWavely((s) => s.sessions);

  if (page === "account") {
    return <AccountView />;
  }

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

      {/* profile hero — tap to open the full Account page */}
      <button
        onClick={() => setPage("account")}
        className="mt-2 flex w-full items-center gap-4 rounded-2xl bg-gradient-to-br from-primary/25 via-primary/10 to-transparent p-4 text-left transition hover:from-primary/35"
        aria-label="Open account & profile"
      >
        <span className="relative h-14 w-14 shrink-0 overflow-hidden rounded-full ring-2 ring-primary/40">
          <Image src={profile.avatar} alt="" fill sizes="56px" unoptimized className="object-cover" />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-base font-extrabold">{profile.name}</span>
          <span className="block truncate text-xs text-muted-foreground">{profile.email}</span>
          <span className="mt-1 inline-flex items-center gap-1 rounded-full bg-primary/20 px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest text-primary">
            <ShieldCheck className="h-3 w-3" /> {profile.plan} plan
          </span>
        </span>
        <ChevronRight className="h-5 w-5 shrink-0 text-muted-foreground" />
      </button>

      <SectionHeader icon={UserRound} title="Account & privacy" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={UserRound} title="Account" subtitle="Profile, plan, sign-out & deletion" onClick={() => setPage("account")} arrow />
        <Separator />
        <Row icon={Smartphone} title="Sessions & devices" subtitle={`${sessions.length} active sign-in${sessions.length === 1 ? "" : "s"}`} onClick={() => setPage("account")} arrow />
        <Separator />
        <Row icon={Cookie} title="Cookies & site data" subtitle="Personalization, analytics & clearing" onClick={() => setPage("account")} arrow />
        <Separator />
        <Row icon={ShieldCheck} title="Security" subtitle="Password, 2FA & security notes" onClick={() => setPage("account")} arrow />
      </div>

      <SectionHeader icon={Palette} title="Appearance" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={Moon} title="Theme" subtitle="Dark (light theme coming later)" />
        <Separator />
        <Row icon={Waves} title="AMOLED black" subtitle="True black background" control={<Switch checked={amoled} onCheckedChange={setAmoled} />} />
        <Separator />
        <Row icon={Palette} title="Accent color" subtitle="Wavely green" control={<span className="h-6 w-6 rounded-full bg-primary ring-2 ring-primary/40" />} />
      </div>

      <SectionHeader icon={Compass} title="Region & languages" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row
          icon={Compass}
          title="Region"
          subtitle="Legal-source availability & metadata market"
          control={
            <Select value={region} onValueChange={setRegion}>
              <SelectTrigger size="sm" className="w-[8.5rem] rounded-full text-xs" aria-label="Region">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {REGIONS.map((r) => (
                  <SelectItem key={r.code} value={r.code}>
                    {r.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          }
        />
        <Separator />
        <Row
          icon={Languages}
          title="Music language priority"
          subtitle={
            musicLanguages.length
              ? musicLanguages.map((c) => MUSIC_LANGUAGES.find((l) => l.code === c)?.name ?? c).join("  →  ")
              : "None set — edit in the setup wizard"
          }
          arrow
          onClick={() => toast({ description: "Reorder in the setup wizard — Settings editing lands with the Flutter build" })}
        />
        <Separator />
        <Row
          icon={Ban}
          title="Never autoplay"
          subtitle={
            neverPlayLanguages.length
              ? neverPlayLanguages.map((c) => MUSIC_LANGUAGES.find((l) => l.code === c)?.name ?? c).join(", ")
              : "Nothing blocked"
          }
        />
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
        <Separator />
        <Row
          icon={Languages}
          title="Translate lyrics"
          subtitle="Line-aligned translation under every original line"
          control={<Switch checked={lyricsTranslate} onCheckedChange={setLyricsTranslate} aria-label="Translate lyrics" />}
        />
        <Separator />
        <Row
          icon={Languages}
          title="Translation language"
          subtitle="Any language — not just Persian"
          control={
            <Select value={lyricsTargetLang} onValueChange={setLyricsTargetLang}>
              <SelectTrigger size="sm" className="w-[8.5rem] rounded-full text-xs" aria-label="Lyrics translation language">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {LYRICS_TARGET_LANGS.map((l) => (
                  <SelectItem key={l.value} value={l.value}>
                    {l.short}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          }
        />
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
            Build the folder structure for saved songs — tokens snap into the template:
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
          {/* the audio file itself — lives INSIDE the last folder, never a folder */}
          <p className="mb-1 text-sm font-medium">File names</p>
          <p className="mb-2 text-xs text-muted-foreground">
            The saved audio file lands inside the last folder:
          </p>
          <Input
            value={fileTemplate}
            onChange={(e) => setFileTemplate(e.target.value)}
            className="mb-2 h-10 font-mono text-xs"
            aria-label="File name template"
            spellCheck={false}
          />
          <div className="no-scrollbar mb-3 flex gap-1.5 overflow-x-auto pb-1">
            {["{track}", "{title}", "{artist}", "{album}", "{year}"].map((tok) => (
              <button
                key={tok}
                onClick={() => {
                  setFileTemplate(fileTemplate ? `${fileTemplate} ${tok}` : tok);
                  toast({ description: `Added ${tok} to the file name` });
                }}
                className="shrink-0 rounded-full bg-secondary px-3 py-1.5 font-mono text-[11px] text-muted-foreground transition hover:bg-accent hover:text-foreground"
              >
                {tok}
              </button>
            ))}
            <button
              onClick={() => setFileTemplate("{artist} - {title}")}
              className="shrink-0 rounded-full px-2.5 py-1.5 text-[11px] text-muted-foreground transition hover:text-foreground"
            >
              Reset
            </button>
          </div>
          <div className="rounded-lg bg-secondary/60 p-2.5 font-mono text-[11px]">
            <p className="mb-1 text-muted-foreground">Preview</p>
            <p className="break-all text-primary" aria-live="polite">
              {downloadPath.replace(/\/$/, "")}/{renderFolderTemplate(folderTemplate || "--", SAMPLE_TRACK)}/
              {renderFileTemplate(fileTemplate, SAMPLE_TRACK)}.{downloadQuality === "flac" ? "flac" : "mp3"}
            </p>
          </div>
        </div>
        <Separator />
        <Row
          icon={Download}
          title="Download quality"
          subtitle="Quality of saved songs"
          control={
            <div className="flex overflow-hidden rounded-full bg-secondary text-xs font-medium">
              {(["320", "flac", "ask"] as const).map((q) => (
                <button
                  key={q}
                  onClick={() => setDownloadQuality(q)}
                  className={cn("px-2.5 py-1.5 transition", downloadQuality === q && "bg-primary text-primary-foreground")}
                >
                  {q === "320" ? "320" : q === "flac" ? "FLAC" : "Ask"}
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

      <SectionHeader icon={Folder} title="Library folders" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        {musicFolders.map((path, i) => (
          <div key={path}>
            {i > 0 && <Separator />}
            <div className="flex w-full items-center gap-3 px-3 py-3">
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-accent text-foreground">
                <Folder className="h-4 w-4" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="break-all font-mono text-xs">{path}</p>
                <p className="text-[11px] text-muted-foreground">
                  Scan root {i + 1} of {musicFolders.length}
                </p>
              </div>
              <button
                onClick={() => {
                  if (musicFolders.length <= 1) {
                    toast({ description: "Wavely needs at least one music folder — add another first" });
                    return;
                  }
                  removeMusicFolder(path);
                  toast({ description: "Folder removed — rescan to update the library" });
                }}
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition hover:bg-accent hover:text-foreground"
                aria-label={`Remove ${path}`}
              >
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
          </div>
        ))}
        <Separator />
        <Row
          icon={FolderPlus}
          title="Add music folder"
          subtitle="Many people keep music in several paths — add them all"
          onClick={addSuggestedFolder}
          arrow
        />
        <Separator />
        <Row
          icon={ScanLine}
          title="Scan all folders"
          subtitle={`Rescans ${musicFolders.length} folder${musicFolders.length === 1 ? "" : "s"} for new songs`}
          onClick={() => toast({ description: `Library scan started — ${musicFolders.length} folder${musicFolders.length === 1 ? "" : "s"}, 34 songs found` })}
          arrow
        />
      </div>

      <SectionHeader icon={DatabaseBackup} title="Backup & restore" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row
          icon={DatabaseBackup}
          title="Automatic backups"
          subtitle="Playlists, queues, play counts & settings"
          control={<Switch checked={backupEnabled} onCheckedChange={setBackupEnabled} aria-label="Automatic backups" />}
        />
        {backupEnabled && (
          <>
            <Separator />
            <Row
              icon={Timer}
              title="Schedule"
              subtitle={`Runs ${BACKUP_AUTO_LABELS[backupAuto].toLowerCase()}`}
              control={
                <div className="flex overflow-hidden rounded-full bg-secondary text-[11px] font-medium">
                  {(Object.keys(BACKUP_AUTO_LABELS) as BackupAuto[]).map((f) => (
                    <button
                      key={f}
                      onClick={() => setBackupAuto(f)}
                      className={cn("px-2 py-1.5 transition", backupAuto === f && "bg-primary text-primary-foreground")}
                    >
                      {f === "onLaunch" ? "Launch" : f === "onExit" ? "Exit" : BACKUP_AUTO_LABELS[f]}
                    </button>
                  ))}
                </div>
              }
            />
          </>
        )}
        <Separator />
        <div className="px-3 py-3">
          <p className="mb-2 text-sm font-medium">Backup location</p>
          <div className="flex gap-2">
            <Input
              value={backupPath}
              onChange={(e) => setBackupPath(e.target.value)}
              className="h-10 flex-1 font-mono text-xs"
              aria-label="Backup path"
              spellCheck={false}
            />
            <Button
              variant="outline"
              size="icon"
              className="h-10 w-10 shrink-0"
              onClick={() => toast({ description: "SAF folder picker opens here in the Flutter app" })}
              aria-label="Choose backup folder"
            >
              <Folder className="h-4 w-4" />
            </Button>
          </div>
          <p className="mt-1.5 text-[11px] text-muted-foreground">Default: {DEFAULT_BACKUP_PATH}</p>
        </div>
        <Separator />
        <Row
          icon={DatabaseBackup}
          title="Back up now"
          subtitle="One archive — library, playlists, counts, settings"
          onClick={() =>
            toast({
              description: `Backup saved to ${backupPath || DEFAULT_BACKUP_PATH} — ${TRACKS.length} songs, playlists & settings included`,
            })
          }
          arrow
        />
        <Separator />
        <Row
          icon={History}
          title="Restore from backup"
          subtitle="Pick a backup file — everything comes back"
          onClick={() => toast({ description: "Restore runs on the installed app — pick a .wavely backup file" })}
          arrow
        />
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
        <Row icon={ScanLine} title="Scan library" subtitle={`Rescan ${musicFolders.length} folder${musicFolders.length === 1 ? "" : "s"} for new songs`} onClick={() => toast({ description: "Library scan started — 34 songs found" })} arrow />
        <Separator />
        <Row icon={Folder} title="Blacklist folders" subtitle="Hide folders from the library" onClick={() => toast({ description: "Folder picker in the full app" })} arrow />
      </div>

      <SectionHeader icon={Lock} title="Parental controls" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={Lock} title="Parental mode" subtitle="Auto-censor swearing · PIN lock on explicit content & settings" control={<Switch checked={parentalMode} onCheckedChange={(v) => { setParentalMode(v); if (v) toast({ description: "PIN setup opens in the full app" }); }} />} />
      </div>

      <SectionHeader icon={Sparkles} title="AI features" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row
          icon={Sparkles}
          title="Enable AI features"
          subtitle="Mood-aware queues and library chat"
          control={<Switch checked={aiFeatures} onCheckedChange={setAiFeatures} aria-label="Enable AI features" />}
        />
        <Separator />
        <Row icon={Info} title="Bring your own key" subtitle="GEMINI_API_KEY or OPENAI_API_KEY in .env — everything stays local" />
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
        <Row icon={Sparkles} title="Replay setup wizard" subtitle="Re-run the first-run onboarding" onClick={() => setOnboardingOpen(true)} arrow />
        <Separator />
        <Row icon={Heart} title="Made with love" subtitle="Musicolet's soul, Spotify's style" />
      </div>

      <p className="pb-2 pt-6 text-center text-xs text-muted-foreground">
        Wavely — free & open source. Settings marked “full app” land in the Flutter build.
      </p>
    </div>
  );
}
