"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import {
  useWavely,
  APP_LANGUAGES,
  LYRICS_TARGET_LANGS,
} from "@/lib/wavely/store";
import { TRACKS } from "@/lib/wavely/data";
import { useToast } from "@/hooks/use-toast";
import { WavelyLogo } from "./logo";
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
  Check,
  ChevronRight,
  Compass,
  Folder,
  Languages,
  Loader2,
  Mic2,
  ScanLine,
  SlidersHorizontal,
  X,
} from "lucide-react";
import { cn } from "@/lib/utils";

const ONBOARDED_FLAG = "wavely-onboarded";

const STEPS = ["Welcome", "Language & lyrics", "Music folder", "Ready"] as const;

/**
 * First-run setup wizard — the design blueprint for the Android onboarding.
 * Steps: welcome → language + lyrics-translation opt-in (user rule #16: the
 * wizard must ASK whether lyrics should be translated, into any language —
 * not Persian-exclusive) → music folder + scan → done.
 * Re-runnable from Settings → About → "Replay setup wizard".
 */
export function OnboardingWizard() {
  const open = useWavely((s) => s.onboardingOpen);
  const setOpen = useWavely((s) => s.setOnboardingOpen);
  const appLanguage = useWavely((s) => s.appLanguage);
  const setAppLanguage = useWavely((s) => s.setAppLanguage);
  const lyricsTranslate = useWavely((s) => s.lyricsTranslate);
  const setLyricsTranslate = useWavely((s) => s.setLyricsTranslate);
  const lyricsTargetLang = useWavely((s) => s.lyricsTargetLang);
  const setLyricsTargetLang = useWavely((s) => s.setLyricsTargetLang);
  const downloadPath = useWavely((s) => s.downloadPath);
  const setDownloadPath = useWavely((s) => s.setDownloadPath);
  const { toast } = useToast();

  const [step, setStep] = useState(0);
  const [scanning, setScanning] = useState(false);
  const [scanned, setScanned] = useState(false);
  const [progress, setProgress] = useState(0);

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

  const finish = () => {
    try {
      localStorage.setItem(ONBOARDED_FLAG, "1");
    } catch {
      /* private mode — wizard just won't auto-open next time */
    }
    setOpen(false);
  };

  const startScan = () => {
    setProgress(0);
    setScanned(false);
    setScanning(true);
  };

  const targetShort =
    LYRICS_TARGET_LANGS.find((l) => l.value === lyricsTargetLang)?.short ??
    lyricsTargetLang;

  if (!open) return null;

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
          {/* progress dots + skip */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5" aria-hidden="true">
              {STEPS.map((s, i) => (
                <span
                  key={s}
                  className={cn(
                    "h-1.5 rounded-full transition-all duration-300",
                    i === step ? "w-6 bg-primary" : i < step ? "w-1.5 bg-primary/50" : "w-1.5 bg-accent",
                  )}
                />
              ))}
            </div>
            {step > 0 && (
              <button
                onClick={finish}
                className="flex items-center gap-1 rounded-full px-2 py-1 text-xs text-muted-foreground transition hover:text-foreground"
              >
                Skip <X className="h-3.5 w-3.5" />
              </button>
            )}
          </div>

          <AnimatePresence mode="wait">
            <motion.div
              key={step}
              initial={{ opacity: 0, x: 28 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -28 }}
              transition={{ duration: 0.22, ease: "easeOut" }}
              className="wavely-scroll flex min-h-0 flex-1 flex-col justify-center overflow-y-auto py-6"
            >
              {/* ---------- step 0 · welcome ---------- */}
              {step === 0 && (
                <div className="flex flex-col items-center text-center">
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
                  <Button className="mt-8 h-11 w-full rounded-full text-sm font-bold" onClick={() => setStep(1)}>
                    Let&apos;s set it up <ChevronRight className="h-4 w-4" />
                  </Button>
                </div>
              )}

              {/* ---------- step 1 · language + lyrics translation opt-in ---------- */}
              {step === 1 && (
                <div>
                  <h1 className="font-display text-2xl font-bold tracking-tight">Pick your language</h1>
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

                  <Button className="mt-6 h-11 w-full rounded-full text-sm font-bold" onClick={() => setStep(2)}>
                    Continue
                  </Button>
                </div>
              )}

              {/* ---------- step 2 · music folder + scan ---------- */}
              {step === 2 && (
                <div>
                  <h1 className="font-display text-2xl font-bold tracking-tight">Where&apos;s your music?</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Point Wavely at your music folder — a quick scan keeps the library in sync.
                  </p>
                  <div className="mt-5 flex gap-2">
                    <Input
                      value={downloadPath}
                      onChange={(e) => setDownloadPath(e.target.value)}
                      className="h-11 flex-1 font-mono text-xs"
                      aria-label="Music folder path"
                      spellCheck={false}
                    />
                    <Button
                      variant="outline"
                      size="icon"
                      className="h-11 w-11 shrink-0 rounded-xl"
                      onClick={() => toast({ description: "SAF folder picker opens here in the Flutter app" })}
                      aria-label="Choose folder"
                    >
                      <Folder className="h-4 w-4" />
                    </Button>
                  </div>

                  <Button
                    variant="outline"
                    className="mt-4 h-11 w-full gap-2 rounded-full"
                    disabled={scanning}
                    onClick={startScan}
                  >
                    {scanning ? <Loader2 className="h-4 w-4 animate-spin" /> : <ScanLine className="h-4 w-4" />}
                    {scanning ? "Scanning…" : "Scan this folder"}
                  </Button>

                  {(scanning || scanned) && (
                    <div className="mt-4" aria-live="polite">
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
                      {scanned && (
                        <p className="mt-2.5 flex items-center gap-1.5 text-sm font-semibold text-primary">
                          <Check className="h-4 w-4" /> {TRACKS.length} songs found
                        </p>
                      )}
                    </div>
                  )}

                  <Button className="mt-6 h-11 w-full rounded-full text-sm font-bold" onClick={() => setStep(3)}>
                    Continue
                  </Button>
                </div>
              )}

              {/* ---------- step 3 · done ---------- */}
              {step === 3 && (
                <div className="flex flex-col items-center text-center">
                  <div className="flex h-16 w-16 items-center justify-center rounded-full bg-primary/15">
                    <Check className="h-8 w-8 text-primary" />
                  </div>
                  <h1 className="mt-5 font-display text-2xl font-bold tracking-tight">You&apos;re all set</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Everything here can be changed later in Settings.
                  </p>
                  <div className="mt-6 w-full space-y-2 text-left text-xs">
                    {[
                      { k: "Language", v: APP_LANGUAGES.find((l) => l.value === appLanguage)?.native ?? appLanguage },
                      { k: "Lyrics translation", v: lyricsTranslate ? `On → ${targetShort}` : "Off" },
                      { k: "Music folder", v: downloadPath },
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
                  <Button className="mt-8 h-11 w-full rounded-full text-sm font-bold" onClick={finish}>
                    Open Wavely
                  </Button>
                </div>
              )}
            </motion.div>
          </AnimatePresence>
        </div>
      </motion.div>
    </AnimatePresence>
  );
}
