"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import {
  useWavely,
  APP_LANGUAGES,
  LYRICS_TARGET_LANGS,
  REGIONS,
  MUSIC_LANGUAGES,
  renderFolderTemplate,
  type DownloadQuality,
} from "@/lib/wavely/store";
import { TRACKS } from "@/lib/wavely/data";
import { useToast } from "@/hooks/use-toast";
import { WavelyLogo, WavelyMark } from "./logo";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  ArrowDown,
  ArrowUp,
  AudioLines,
  Ban,
  Check,
  ChevronLeft,
  ChevronRight,
  CircleHelp,
  Compass,
  Disc3,
  Folder,
  FolderPlus,
  Languages,
  Loader2,
  Mic2,
  Music2,
  ScanLine,
  SlidersHorizontal,
  Sparkles,
  UsersRound,
  X,
} from "lucide-react";
import { cn } from "@/lib/utils";

const ONBOARDED_FLAG = "wavely-onboarded";

const STEPS = [
  "Welcome",
  "Language & lyrics",
  "Region",
  "Music languages",
  "Download quality",
  "Storage layout",
  "Parental mode",
  "AI features",
  "Music folders",
  "Ready",
] as const;

const QUALITY_OPTIONS: {
  q: DownloadQuality;
  icon: React.ElementType;
  title: string;
  desc: string;
}[] = [
  { q: "320", icon: AudioLines, title: "320 kbps", desc: "Great quality, smaller files" },
  { q: "flac", icon: Disc3, title: "FLAC — lossless", desc: "Up to 24-bit / 192 kHz, bit-perfect" },
  { q: "ask", icon: CircleHelp, title: "Ask every time", desc: "Choose per download" },
];

const FOLDER_SUGGESTIONS = [
  "/storage/emulated/0/Music",
  "/storage/0000-0000/Music",
  "/storage/emulated/0/Download/Music",
  "/sdcard/Music",
];

const LAYOUT_SAMPLE = {
  artist: "Nova Reign",
  album: "Midnight Static",
  title: "Neon Skyline",
  year: 2025,
  genre: "Synthwave",
  country: "US",
};

/**
 * First-run setup wizard — the design blueprint for the Android onboarding.
 * 10 steps, matching the installed build the user loved: welcome → language +
 * lyrics-translation opt-in (#16, any language) → region → music-language
 * priority & never-play → download quality → storage layout → parental mode →
 * AI features → music folders (MULTIPLE paths — users own several) → ready.
 * Re-runnable from Settings → About → "Replay setup wizard".
 */

/**
 * Thin gate — the wizard body remounts fresh on every open, so "Replay setup
 * wizard" always starts from step 1.
 */
export function OnboardingWizard() {
  const open = useWavely((s) => s.onboardingOpen);
  if (!open) return null;
  return <WizardBody />;
}

function WizardBody() {
  const setOpen = useWavely((s) => s.setOnboardingOpen);
  const appLanguage = useWavely((s) => s.appLanguage);
  const setAppLanguage = useWavely((s) => s.setAppLanguage);
  const lyricsTranslate = useWavely((s) => s.lyricsTranslate);
  const setLyricsTranslate = useWavely((s) => s.setLyricsTranslate);
  const lyricsTargetLang = useWavely((s) => s.lyricsTargetLang);
  const setLyricsTargetLang = useWavely((s) => s.setLyricsTargetLang);
  const region = useWavely((s) => s.region);
  const setRegion = useWavely((s) => s.setRegion);
  const musicLanguages = useWavely((s) => s.musicLanguages);
  const neverPlayLanguages = useWavely((s) => s.neverPlayLanguages);
  const addMusicLanguage = useWavely((s) => s.addMusicLanguage);
  const removeMusicLanguage = useWavely((s) => s.removeMusicLanguage);
  const moveMusicLanguage = useWavely((s) => s.moveMusicLanguage);
  const toggleNeverPlayLanguage = useWavely((s) => s.toggleNeverPlayLanguage);
  const downloadQuality = useWavely((s) => s.downloadQuality);
  const setDownloadQuality = useWavely((s) => s.setDownloadQuality);
  const folderTemplate = useWavely((s) => s.folderTemplate);
  const setFolderTemplate = useWavely((s) => s.setFolderTemplate);
  const parentalMode = useWavely((s) => s.parentalMode);
  const setParentalMode = useWavely((s) => s.setParentalMode);
  const aiFeatures = useWavely((s) => s.aiFeatures);
  const setAiFeatures = useWavely((s) => s.setAiFeatures);
  const musicFolders = useWavely((s) => s.musicFolders);
  const addMusicFolder = useWavely((s) => s.addMusicFolder);
  const removeMusicFolder = useWavely((s) => s.removeMusicFolder);
  const downloadPath = useWavely((s) => s.downloadPath);
  const { toast } = useToast();

  const [step, setStep] = useState(0);
  const [scanning, setScanning] = useState(false);
  const [scanned, setScanned] = useState(false);
  const [progress, setProgress] = useState(0);
  const [tz] = useState(() => {
    try {
      return Intl.DateTimeFormat().resolvedOptions().timeZone ?? "";
    } catch {
      return "";
    }
  });

  /* simulated library scan (the Flutter build uses MediaStore + folder scan) */
  useEffect(() => {
    if (!scanning) return;
    const id = setInterval(() => {
      setProgress((p) => {
        const next = p + 100 / 24;
        if (next >= 100) {
          clearInterval(id);
          setScanning(false);
          setScanned(true);
          return 100;
        }
        return next;
      });
    }, 50);
    return () => clearInterval(id);
  }, [scanning]);

  /* "Scan starts after setup" — triggered when the user leaves the folders step */
  const startScan = () => {
    setProgress(0);
    setScanned(false);
    setScanning(true);
  };

  const finish = () => {
    try {
      localStorage.setItem(ONBOARDED_FLAG, "1");
    } catch {
      /* private mode — wizard just won't auto-open next time */
    }
    setOpen(false);
  };

  const next = () => {
    // leaving the music-folders step → the first scan starts right after setup
    if (step === STEPS.length - 2) startScan();
    setStep((s) => Math.min(s + 1, STEPS.length - 1));
  };
  const back = () => setStep((s) => Math.max(s - 1, 0));

  const addSuggestedFolder = () => {
    const suggestion =
      FOLDER_SUGGESTIONS.find((f) => !musicFolders.includes(f)) ??
      `/storage/emulated/0/Music/Folder-${musicFolders.length + 1}`;
    addMusicFolder(suggestion);
  };

  const removeFolder = (path: string) => {
    if (musicFolders.length <= 1) {
      toast({ description: "Wavely needs at least one music folder — add another first" });
      return;
    }
    removeMusicFolder(path);
  };

  const targetShort =
    LYRICS_TARGET_LANGS.find((l) => l.value === lyricsTargetLang)?.short ??
    lyricsTargetLang;

  const regionName = REGIONS.find((r) => r.code === region)?.name ?? region;
  const previewParts = renderFolderTemplate(folderTemplate || "--", LAYOUT_SAMPLE).split("/");
  const qualityLabel =
    downloadQuality === "320" ? "320 kbps" : downloadQuality === "flac" ? "FLAC" : "Ask every time";
  const rootFolderName = downloadPath.replace(/\/+$/, "").split("/").pop() || "Music";

  const nextLabel =
    step === 0 ? "Get started" : step === STEPS.length - 1 ? "Open Wavely" : "Next";

  return (
    <AnimatePresence>
      <motion.div
        key="wizard"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        transition={{ duration: 0.2 }}
        className="fixed inset-0 z-[60] flex flex-col bg-background"
        role="dialog"
        aria-modal="true"
        aria-label="Wavely setup"
      >
        <div className="mx-auto flex h-full w-full max-w-md flex-col px-6 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-[max(1.25rem,env(safe-area-inset-top))]">
          {/* ---------- header: mark · title · step counter · skip ---------- */}
          <div className="flex items-center gap-3">
            <WavelyMark size={40} />
            <p className="font-display text-xl font-bold tracking-tight">Set up Wavely</p>
            <div className="ms-auto flex items-center gap-2">
              <span className="text-sm tabular-nums text-muted-foreground" aria-live="polite">
                {step + 1} / {STEPS.length}
              </span>
              {step > 0 && step < STEPS.length - 1 && (
                <button
                  onClick={finish}
                  className="flex items-center gap-1 rounded-full px-2 py-1 text-xs text-muted-foreground transition hover:text-foreground"
                  aria-label="Skip setup"
                >
                  Skip <X className="h-3.5 w-3.5" />
                </button>
              )}
            </div>
          </div>
          {/* thin determinate progress bar */}
          <div className="mt-3 h-1 w-full overflow-hidden rounded-full bg-secondary">
            <div
              className="h-full rounded-full bg-primary transition-all duration-300"
              style={{ width: `${((step + 1) / STEPS.length) * 100}%` }}
              role="progressbar"
              aria-valuenow={step + 1}
              aria-valuemin={1}
              aria-valuemax={STEPS.length}
              aria-label="Setup progress"
            />
          </div>

          <AnimatePresence mode="wait">
            <motion.div
              key={step}
              initial={{ opacity: 0, x: 28 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -28 }}
              transition={{ duration: 0.22, ease: "easeOut" }}
              className="wavely-scroll min-h-0 flex-1 overflow-y-auto py-6"
            >
              {/* ---------- step 0 · welcome ---------- */}
              {step === 0 && (
                <div className="flex h-full flex-col items-center justify-center text-center">
                  <WavelyLogo size={64} showWordmark />
                  <p className="mt-6 max-w-xs text-balance text-sm leading-relaxed text-muted-foreground">
                    Musicolet&apos;s soul, Spotify&apos;s style — a free, open-source player for
                    the music actually on your phone.
                  </p>
                  <div className="mt-8 w-full space-y-2.5 text-left">
                    {[
                      { icon: Mic2, title: "Synced lyrics", desc: "Auto-fetched, translated, tap-to-jump" },
                      { icon: Compass, title: "My Music × Explore", desc: "Offline library plus online discovery" },
                      { icon: SlidersHorizontal, title: "Real power", desc: "10-band EQ, 20 queues, sleep timer, folders" },
                    ].map(({ icon: Icon, title, desc }) => (
                      <div key={title} className="flex items-center gap-3 rounded-2xl bg-wav-surface p-3">
                        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-accent">
                          <Icon className="h-4 w-4 text-primary" />
                        </div>
                        <div className="min-w-0">
                          <p className="text-sm font-semibold">{title}</p>
                          <p className="truncate text-xs text-muted-foreground">{desc}</p>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* ---------- step 1 · language + lyrics translation opt-in ---------- */}
              {step === 1 && (
                <div>
                  <h1 className="font-display text-3xl font-bold tracking-tight">Pick your language</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    The app language — full RTL layouts land with the Flutter build.
                  </p>
                  <div className="mt-5 grid grid-cols-2 gap-2" role="radiogroup" aria-label="App language">
                    {APP_LANGUAGES.map((l) => {
                      const active = appLanguage === l.value;
                      return (
                        <button
                          key={l.value}
                          onClick={() => {
                            setAppLanguage(l.value);
                            // convenience: default the lyrics target to the app language
                            setLyricsTargetLang(l.value);
                          }}
                          className={cn(
                            "flex items-center justify-between rounded-xl bg-wav-surface px-3.5 py-3 text-sm font-semibold transition",
                            active ? "ring-2 ring-primary" : "hover:bg-accent/60",
                          )}
                          role="radio"
                          aria-checked={active}
                        >
                          <span>{l.native}</span>
                          {active && <Check className="h-4 w-4 shrink-0 text-primary" />}
                        </button>
                      );
                    })}
                  </div>

                  {/* the #16 rule: wizard ASKS about translation — any language */}
                  <div className="mt-6 rounded-2xl bg-wav-surface p-4">
                    <div className="flex items-center justify-between gap-3">
                      <div className="flex min-w-0 items-center gap-2.5">
                        <Languages className="h-4 w-4 shrink-0 text-primary" />
                        <div className="min-w-0">
                          <p className="text-sm font-semibold">Translate lyrics for me</p>
                          <p className="text-xs text-muted-foreground">
                            Under every original line — any language
                          </p>
                        </div>
                      </div>
                      <Switch
                        checked={lyricsTranslate}
                        onCheckedChange={setLyricsTranslate}
                        aria-label="Translate lyrics"
                      />
                    </div>
                    {lyricsTranslate && (
                      <div className="mt-3">
                        <Select value={lyricsTargetLang} onValueChange={setLyricsTargetLang}>
                          <SelectTrigger className="h-9 w-full rounded-lg text-xs" aria-label="Lyrics translation language">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent className="z-[70]">
                            {LYRICS_TARGET_LANGS.map((l) => (
                              <SelectItem key={l.value} value={l.value}>
                                {l.short}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <p className="mt-2 text-[11px] leading-relaxed text-muted-foreground">
                          Not Persian-exclusive — Russian into Russian, Turkish into Turkish.
                          Changeable later in Settings → Lyrics.
                        </p>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* ---------- step 2 · region ---------- */}
              {step === 2 && (
                <div>
                  <h1 className="font-display text-3xl font-bold tracking-tight">Region</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Used for legal-source availability and metadata.
                  </p>
                  <div className="mt-5 flex flex-wrap gap-2" role="radiogroup" aria-label="Region">
                    {REGIONS.map((r) => {
                      const active = region === r.code;
                      return (
                        <button
                          key={r.code}
                          onClick={() => setRegion(r.code)}
                          role="radio"
                          aria-checked={active}
                          className={cn(
                            "flex items-center gap-2 rounded-full px-4 py-2.5 text-sm font-semibold transition",
                            active
                              ? "bg-accent text-primary ring-2 ring-primary"
                              : "bg-wav-surface text-foreground hover:bg-accent/60",
                          )}
                        >
                          {active ? (
                            <Check className="h-4 w-4 shrink-0" />
                          ) : (
                            <span className="text-[10px] font-bold tracking-widest text-muted-foreground">
                              {r.code}
                            </span>
                          )}
                          {r.name}
                        </button>
                      );
                    })}
                  </div>

                  {/* country-code field with floating legend label */}
                  <div className="relative mt-6 rounded-xl border border-border bg-wav-surface px-3 pb-2 pt-3">
                    <span className="absolute -top-2 left-3 bg-background px-1.5 text-[11px] text-muted-foreground">
                      Country code
                    </span>
                    <input
                      value={region}
                      onChange={(e) => setRegion(e.target.value)}
                      maxLength={2}
                      aria-label="Country code"
                      className="w-full bg-transparent text-lg font-semibold uppercase tracking-wide outline-none"
                      spellCheck={false}
                    />
                  </div>
                  <p className="mt-2.5 text-[11px] text-muted-foreground">
                    {tz
                      ? `Auto-detected from your timezone (${tz}) — change any time.`
                      : "Auto-detection unavailable — using locale fallback. Change any time."}
                  </p>
                </div>
              )}

              {/* ---------- step 3 · music languages: priority + never play ---------- */}
              {step === 3 && (
                <div>
                  <h1 className="font-display text-3xl font-bold tracking-tight">Languages</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Priority order first — then anything Wavely must never autoplay.
                  </p>

                  <h2 className="mt-6 text-base font-bold">Priority order</h2>
                  <p className="text-xs text-muted-foreground">Tap the arrows to reorder.</p>
                  <div className="mt-2 space-y-2" aria-label="Priority languages">
                    {musicLanguages.map((code, i) => {
                      const lang = MUSIC_LANGUAGES.find((l) => l.code === code);
                      return (
                        <div
                          key={code}
                          className="flex items-center gap-3 rounded-xl bg-wav-surface px-3 py-2"
                        >
                          <span className="w-4 text-sm font-bold tabular-nums text-primary">
                            {i + 1}
                          </span>
                          <span className="min-w-0 flex-1 truncate text-sm font-semibold">
                            {lang?.name ?? code}
                            <span className="ms-2 text-xs font-normal text-muted-foreground">{code}</span>
                          </span>
                          <button
                            onClick={() => moveMusicLanguage(code, -1)}
                            disabled={i === 0}
                            className="flex h-9 w-9 items-center justify-center rounded-lg transition hover:bg-accent disabled:opacity-30"
                            aria-label={`Move ${lang?.name ?? code} up`}
                          >
                            <ArrowUp className="h-4 w-4" />
                          </button>
                          <button
                            onClick={() => moveMusicLanguage(code, 1)}
                            disabled={i === musicLanguages.length - 1}
                            className="flex h-9 w-9 items-center justify-center rounded-lg transition hover:bg-accent disabled:opacity-30"
                            aria-label={`Move ${lang?.name ?? code} down`}
                          >
                            <ArrowDown className="h-4 w-4" />
                          </button>
                          <button
                            onClick={() => removeMusicLanguage(code)}
                            className="flex h-9 w-9 items-center justify-center rounded-lg transition hover:bg-accent"
                            aria-label={`Remove ${lang?.name ?? code} from priority`}
                          >
                            <X className="h-4 w-4" />
                          </button>
                        </div>
                      );
                    })}
                    {musicLanguages.length === 0 && (
                      <p className="rounded-xl bg-wav-surface px-3 py-3 text-xs text-muted-foreground">
                        No priority languages — add the ones you actually listen to.
                      </p>
                    )}
                  </div>

                  {/* add-to-priority chips (languages not listed yet) */}
                  {MUSIC_LANGUAGES.some((l) => !musicLanguages.includes(l.code) && !neverPlayLanguages.includes(l.code)) && (
                    <>
                      <h2 className="mt-5 text-sm font-bold text-muted-foreground">Tap to add</h2>
                      <div className="mt-2 flex flex-wrap gap-2">
                        {MUSIC_LANGUAGES.filter(
                          (l) => !musicLanguages.includes(l.code) && !neverPlayLanguages.includes(l.code),
                        ).map((l) => (
                          <button
                            key={l.code}
                            onClick={() => addMusicLanguage(l.code)}
                            className="rounded-full bg-wav-surface px-3.5 py-2 text-xs font-semibold transition hover:bg-accent/60"
                          >
                            + {l.name}
                          </button>
                        ))}
                      </div>
                    </>
                  )}

                  <h2 className="mt-7 text-base font-bold">Never play</h2>
                  <p className="text-xs text-muted-foreground">
                    Wavely will never autoplay songs in these languages.
                  </p>
                  <div className="mt-2 flex flex-wrap gap-2">
                    {MUSIC_LANGUAGES.filter((l) => !musicLanguages.includes(l.code)).map((l) => {
                      const banned = neverPlayLanguages.includes(l.code);
                      return (
                        <button
                          key={l.code}
                          onClick={() => toggleNeverPlayLanguage(l.code)}
                          aria-pressed={banned}
                          className={cn(
                            "flex items-center gap-1.5 rounded-full px-3.5 py-2 text-xs font-semibold transition",
                            banned
                              ? "bg-accent text-primary ring-2 ring-primary"
                              : "bg-wav-surface hover:bg-accent/60",
                          )}
                        >
                          {banned && <Ban className="h-3 w-3" />}
                          {l.name}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* ---------- step 4 · download quality ---------- */}
              {step === 4 && (
                <div>
                  <h1 className="font-display text-3xl font-bold tracking-tight">Download quality</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Applies when you save songs from Explore.
                  </p>
                  <div className="mt-5 space-y-3" role="radiogroup" aria-label="Download quality">
                    {QUALITY_OPTIONS.map(({ q, icon: Icon, title, desc }) => {
                      const active = downloadQuality === q;
                      return (
                        <button
                          key={q}
                          onClick={() => setDownloadQuality(q)}
                          role="radio"
                          aria-checked={active}
                          className={cn(
                            "flex w-full items-center gap-3.5 rounded-2xl bg-wav-surface p-4 text-left transition",
                            active ? "ring-2 ring-primary" : "hover:bg-accent/60",
                          )}
                        >
                          <div
                            className={cn(
                              "flex h-12 w-12 shrink-0 items-center justify-center rounded-xl",
                              active ? "bg-primary text-primary-foreground" : "bg-primary/15 text-primary",
                            )}
                          >
                            <Icon className="h-5 w-5" />
                          </div>
                          <div className="min-w-0 flex-1">
                            <p className={cn("text-sm font-bold", active && "text-primary")}>{title}</p>
                            <p className="truncate text-xs text-muted-foreground">{desc}</p>
                          </div>
                          <span
                            className={cn(
                              "flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2",
                              active ? "border-primary bg-primary" : "border-muted-foreground/40",
                            )}
                          >
                            {active && <Check className="h-3.5 w-3.5 text-primary-foreground" />}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* ---------- step 5 · storage layout ---------- */}
              {step === 5 && (
                <div>
                  <h1 className="font-display text-3xl font-bold tracking-tight">Storage layout</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    How downloads are organised on disk.
                  </p>

                  <div className="relative mt-5 rounded-xl border border-border bg-wav-surface px-3 pb-2 pt-3">
                    <span className="absolute -top-2 left-3 bg-background px-1.5 text-[11px] text-muted-foreground">
                      Template
                    </span>
                    <Input
                      value={folderTemplate}
                      onChange={(e) => setFolderTemplate(e.target.value)}
                      className="h-7 border-0 bg-transparent p-0 font-mono text-sm shadow-none focus-visible:ring-0"
                      aria-label="Folder template"
                      spellCheck={false}
                    />
                  </div>
                  <p className="mt-2 flex flex-wrap items-center gap-1.5 text-[11px] text-muted-foreground">
                    Tokens:
                    {["{artist}", "{album}", "{title}", "{year}", "{country}", "{genre}"].map((tok) => (
                      <button
                        key={tok}
                        onClick={() => setFolderTemplate(folderTemplate ? `${folderTemplate}/${tok}` : tok)}
                        className="rounded-full bg-secondary px-2 py-0.5 font-mono transition hover:bg-accent hover:text-foreground"
                      >
                        {tok}
                      </button>
                    ))}
                  </p>

                  {/* live preview tree */}
                  <div className="mt-5 rounded-2xl bg-wav-surface p-4">
                    <p className="text-sm font-bold">Preview</p>
                    <div className="mt-3 space-y-1.5 text-sm">
                      <div className="flex items-center gap-2 font-semibold">
                        <Folder className="h-4 w-4 text-primary" />
                        {rootFolderName}/
                      </div>
                      {previewParts.map((part, i) => {
                        const isFile = i === previewParts.length - 1;
                        return (
                          <div
                            key={`${part}-${i}`}
                            className="flex items-center gap-2 text-muted-foreground"
                            style={{ paddingInlineStart: `${(i + 1) * 1.25}rem` }}
                          >
                            {isFile ? (
                              <>
                                <Music2 className="h-4 w-4 text-primary/70" />
                                <span className="text-foreground/80">
                                  {part}.{downloadQuality === "flac" ? "flac" : "mp3"}
                                </span>
                              </>
                            ) : (
                              <>
                                <Folder className="h-4 w-4 text-primary/70" />
                                <span>{part}/</span>
                              </>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  </div>
                </div>
              )}

              {/* ---------- step 6 · parental mode ---------- */}
              {step === 6 && (
                <div>
                  <h1 className="font-display text-3xl font-bold tracking-tight">Parental mode</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Pin-protected, starter block list — configurable any time in Settings.
                  </p>
                  <div className="mt-5 rounded-2xl bg-wav-surface p-4">
                    <div className="flex items-center justify-between gap-3">
                      <div className="flex min-w-0 items-center gap-3">
                        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary/15">
                          <UsersRound className="h-5 w-5 text-primary" />
                        </div>
                        <div className="min-w-0">
                          <p className="text-sm font-bold">Enable parental mode</p>
                          <p className="text-xs text-muted-foreground">
                            Auto-censor swearing · PIN lock
                          </p>
                        </div>
                      </div>
                      <Switch
                        checked={parentalMode}
                        onCheckedChange={setParentalMode}
                        aria-label="Enable parental mode"
                      />
                    </div>
                    {parentalMode && (
                      <p className="mt-3 text-[11px] leading-relaxed text-muted-foreground">
                        You&apos;ll choose the PIN on first launch — explicit songs stay hidden
                        until it&apos;s entered.
                      </p>
                    )}
                  </div>
                </div>
              )}

              {/* ---------- step 7 · AI features ---------- */}
              {step === 7 && (
                <div>
                  <h1 className="font-display text-3xl font-bold tracking-tight">AI features</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Optional — bring your own key, everything stays local.
                  </p>
                  <div className="mt-5 rounded-2xl bg-wav-surface p-4">
                    <div className="flex items-center justify-between gap-3">
                      <div className="flex min-w-0 items-center gap-3">
                        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary/15">
                          <Sparkles className="h-5 w-5 text-primary" />
                        </div>
                        <div className="min-w-0">
                          <p className="text-sm font-bold">Enable AI features</p>
                          <p className="text-xs text-muted-foreground">
                            Mood-aware queues and library chat
                          </p>
                        </div>
                      </div>
                      <Switch
                        checked={aiFeatures}
                        onCheckedChange={setAiFeatures}
                        aria-label="Enable AI features"
                      />
                    </div>
                  </div>
                  <p className="mt-4 text-[13px] leading-relaxed text-muted-foreground">
                    Bring your own key: set GEMINI_API_KEY or OPENAI_API_KEY in .env (see
                    .env.example).
                  </p>
                  <p className="mt-3 text-[13px] leading-relaxed text-muted-foreground">
                    You can skip this — enable later in Settings.
                  </p>
                </div>
              )}

              {/* ---------- step 8 · music folders (MULTIPLE) ---------- */}
              {step === 8 && (
                <div>
                  <h1 className="font-display text-3xl font-bold tracking-tight">Music folders</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Pick where your audio lives — the first scan starts right after setup.
                  </p>

                  <Button
                    variant="outline"
                    className="mt-5 h-12 gap-2 rounded-full px-6 text-sm font-bold"
                    onClick={addSuggestedFolder}
                  >
                    <FolderPlus className="h-4 w-4" /> Add music folder
                  </Button>

                  <div className="mt-4 space-y-2" aria-label="Music folders">
                    {musicFolders.map((path) => (
                      <div
                        key={path}
                        className="flex items-center gap-3 rounded-xl bg-wav-surface px-3 py-2.5"
                      >
                        <Folder className="h-4 w-4 shrink-0 text-primary" />
                        <span className="min-w-0 flex-1 break-all font-mono text-xs">{path}</span>
                        <button
                          onClick={() => removeFolder(path)}
                          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg transition hover:bg-accent"
                          aria-label={`Remove ${path}`}
                        >
                          <X className="h-4 w-4" />
                        </button>
                      </div>
                    ))}
                  </div>
                  <p className="mt-3 text-xs text-muted-foreground" aria-live="polite">
                    {musicFolders.length} folder{musicFolders.length === 1 ? "" : "s"} will be scanned.
                  </p>
                  <p className="mt-1 text-xs text-muted-foreground">Scan starts after setup.</p>
                </div>
              )}

              {/* ---------- step 9 · ready ---------- */}
              {step === 9 && (
                <div className="flex flex-col items-center text-center">
                  <div className="flex h-16 w-16 items-center justify-center rounded-full bg-primary/15">
                    <Check className="h-8 w-8 text-primary" />
                  </div>
                  <h1 className="mt-5 font-display text-2xl font-bold tracking-tight">You&apos;re all set</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Everything here can be changed later in Settings.
                  </p>

                  {/* scan that "starts after setup" */}
                  <div className="mt-5 w-full" aria-live="polite">
                    <div
                      className="h-2 w-full overflow-hidden rounded-full bg-secondary"
                      role="progressbar"
                      aria-valuenow={Math.round(progress)}
                      aria-valuemin={0}
                      aria-valuemax={100}
                      aria-label="Library scan progress"
                    >
                      <div
                        className="h-full rounded-full bg-primary transition-all duration-150"
                        style={{ width: `${progress}%` }}
                      />
                    </div>
                    <p className="mt-2 flex items-center justify-center gap-1.5 text-sm font-semibold">
                      {scanning ? (
                        <>
                          <Loader2 className="h-4 w-4 animate-spin text-primary" />
                          Scanning {musicFolders.length} folder{musicFolders.length === 1 ? "" : "s"}…
                        </>
                      ) : (
                        <span className="text-primary">
                          <Check className="mr-1 inline h-4 w-4" />
                          {TRACKS.length} songs found across {musicFolders.length} folder
                          {musicFolders.length === 1 ? "" : "s"}
                        </span>
                      )}
                    </p>
                  </div>

                  <div className="mt-5 w-full space-y-2 text-left text-xs">
                    {[
                      { k: "Region", v: `${region} — ${regionName}` },
                      { k: "Language", v: APP_LANGUAGES.find((l) => l.value === appLanguage)?.native ?? appLanguage },
                      { k: "Lyrics translation", v: lyricsTranslate ? `On → ${targetShort}` : "Off" },
                      { k: "Download quality", v: qualityLabel },
                      { k: "Storage layout", v: folderTemplate || "--" },
                      { k: "Music folders", v: `${musicFolders.length} — ${musicFolders[0] ?? "--"}` },
                      ...(parentalMode ? [{ k: "Parental mode", v: "On" }] : []),
                      ...(aiFeatures ? [{ k: "AI features", v: "On" }] : []),
                    ].map((r) => (
                      <div
                        key={r.k}
                        className="flex items-center justify-between gap-3 rounded-xl bg-wav-surface px-3.5 py-2.5"
                      >
                        <span className="shrink-0 text-muted-foreground">{r.k}</span>
                        <span className="truncate font-semibold" dir="auto">
                          {r.v}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </motion.div>
          </AnimatePresence>

          {/* ---------- footer: back · dots · next ---------- */}
          <div className="flex items-center justify-between gap-3 rounded-full bg-wav-surface p-2 ps-5">
            <button
              onClick={back}
              disabled={step === 0}
              className="flex items-center gap-1 text-sm font-semibold transition hover:text-primary disabled:opacity-30"
              aria-label="Back"
            >
              <ChevronLeft className="h-4 w-4" /> Back
            </button>
            <div className="flex items-center gap-1.5" aria-hidden="true">
              {STEPS.map((s, i) => (
                <span
                  key={s}
                  className={cn(
                    "h-1.5 rounded-full transition-all duration-300",
                    i === step ? "w-6 bg-primary" : "w-1.5 bg-muted-foreground/30",
                  )}
                />
              ))}
            </div>
            <Button
              className="h-11 gap-1 rounded-full px-6 text-sm font-bold"
              onClick={step === STEPS.length - 1 ? finish : next}
            >
              {nextLabel} <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </motion.div>
    </AnimatePresence>
  );
}
