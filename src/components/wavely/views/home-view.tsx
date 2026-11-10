"use client";

import Image from "next/image";
import { useMemo, useState } from "react";
import { SongRow } from "../song-row";
import { CuratedCard, ReleaseCard } from "../cards";
import { OfflineBanner } from "../source-mode-chips";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import {
  ALBUMS,
  ARTISTS,
  FOLLOWED_ARTIST_IDS,
  MOODS,
  TRACKS,
  albumCover,
  artistById,
  fmtAge,
  trackById,
  tracksOfArtist,
} from "@/lib/wavely/data";
import type { MoodDef } from "@/lib/wavely/data";
import type { Artist } from "@/lib/wavely/types";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";
import {
  ArrowDownToLine,
  ArrowRight,
  Brain,
  Car,
  CloudDownload,
  CloudOff,
  Coffee,
  Compass,
  Disc3,
  Dumbbell,
  Flame,
  Heart,
  MoonStar,
  PartyPopper,
  Play,
  Sparkles,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

function greeting(): string {
  const h = new Date().getHours();
  if (h < 5) return "Good night";
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  if (h < 22) return "Good evening";
  return "Good night";
}

/** Rail: horizontal snap-scroll on mobile → auto-fill grid on desktop (no scroll). */
function Rail({ children, label }: { children: React.ReactNode; label: string }) {
  return (
    <div
      role="group"
      aria-label={label}
      className="no-scrollbar -mx-4 flex snap-x snap-proximity scroll-pl-4 gap-3 overflow-x-auto px-4 pb-1 md:mx-0 md:snap-none md:grid md:grid-cols-[repeat(auto-fill,minmax(150px,1fr))] md:overflow-visible md:px-0"
    >
      {children}
    </div>
  );
}

/** Shared pill toggle for section-level windows ("1 week / 2 weeks / 1 month"). */
function Segmented<T extends string | number>({
  options,
  value,
  onChange,
  ariaLabel,
}: {
  options: ReadonlyArray<{ value: T; label: string }>;
  value: T;
  onChange: (v: T) => void;
  ariaLabel: string;
}) {
  return (
    <div className="flex shrink-0 items-center gap-1" role="group" aria-label={ariaLabel}>
      {options.map((o) => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          aria-pressed={value === o.value}
          className={cn(
            "h-7 rounded-full px-3 text-[11px] font-bold transition",
            value === o.value
              ? "bg-primary text-primary-foreground"
              : "bg-secondary text-muted-foreground hover:bg-accent",
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

/* ---------------------------------------------------------------- */
/* Compact header — avatar + greeting + search, one row, no waste    */
/* ---------------------------------------------------------------- */
function HomeHeader() {
  const setView = useWavely((s) => s.setView);
  return (
    <header className="sticky top-0 z-20 -mx-4 bg-background/85 px-4 pb-2.5 pt-[max(0.5rem,env(safe-area-inset-top))] backdrop-blur-xl md:-mx-8 md:px-8">
      <div className="flex items-center gap-3">
        <button
          onClick={() => setView("settings")}
          className="relative h-10 w-10 shrink-0 overflow-hidden rounded-full ring-2 ring-primary/40 transition hover:ring-primary"
          aria-label="Open profile"
        >
          <Image src="/wavely/avatar.png" alt="Your profile" fill sizes="40px" className="object-cover" />
        </button>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[10px] font-semibold uppercase tracking-[0.2em] text-muted-foreground">
            {greeting()}
          </p>
          <h1 className="truncate font-display text-xl font-extrabold leading-tight tracking-tight">
            Hi, Dani
          </h1>
        </div>
        <button
          onClick={() => setView("search")}
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-wav-elevated text-foreground transition hover:bg-accent"
          aria-label="Search"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" className="h-5 w-5" aria-hidden="true">
            <circle cx="11" cy="11" r="7" />
            <path d="m20 20-3.5-3.5" strokeLinecap="round" />
          </svg>
        </button>
      </div>
    </header>
  );
}

/* ---------------------------------------------------------------- */
/* Quick access — swipeable smart cards, each with an inline play    */
/* button (replaces the old shortcut chips + liked hero section)     */
/* ---------------------------------------------------------------- */
function QuickAccessRow() {
  const setView = useWavely((s) => s.setView);
  const setLibraryTab = useWavely((s) => s.setLibraryTab);
  const setSongSort = useWavely((s) => s.setSongSort);
  const setSongFilter = useWavely((s) => s.setSongFilter);
  const playContext = useWavely((s) => s.playContext);
  const toggleShuffle = useWavely((s) => s.toggleShuffle);
  const isOffline = useWavely((s) => s.isOffline);
  const favIds = useWavely((s) => s.favorites);
  const cachedIds = useWavely((s) => s.cachedIds);
  const { toast } = useToast();

  // offline shrinks every pool to what can actually play right now
  const playable = (ids: string[]) =>
    isOffline
      ? ids.filter((id) => {
          const t = trackById.get(id);
          return !!t && (t.origin === "local" || !!t.downloaded);
        })
      : ids;

  const playIds = (name: string, ids: string[]) => {
    const list = playable(ids);
    if (list.length === 0) {
      toast({ description: isOffline ? "This mix needs internet" : "Nothing here yet" });
      return;
    }
    playContext(name, list, Math.floor(Math.random() * list.length));
  };

  const saved = useMemo(() => TRACKS.filter((t) => t.downloaded).map((t) => t.id), []);
  const mostPlayed = useMemo(
    () => [...TRACKS].sort((a, b) => b.playCount - a.playCount).slice(0, 12).map((t) => t.id),
    [],
  );
  const newMusic = useMemo(
    () => [...TRACKS].sort((a, b) => b.addedAt - a.addedAt).slice(0, 12).map((t) => t.id),
    [],
  );

  interface QuickCard {
    key: string;
    label: string;
    meta: string;
    icon: LucideIcon;
    tile: string;
    solid?: boolean;
    open: () => void;
    play: () => void;
  }

  const cards: QuickCard[] = [
    {
      key: "liked",
      label: "Liked songs",
      meta: `${favIds.length} songs`,
      icon: Heart,
      tile: "bg-primary text-primary-foreground shadow-md accent-glow",
      solid: true,
      open: () => {
        setLibraryTab("favorites");
        setSongFilter("all");
        setView("library");
      },
      play: () => {
        if (playable(favIds).length === 0) {
          toast({ description: isOffline ? "Liked songs need internet" : "No liked songs yet" });
          return;
        }
        playContext("Liked songs", favIds, Math.floor(Math.random() * favIds.length));
        if (!useWavely.getState().shuffle) toggleShuffle();
      },
    },
    {
      key: "most",
      label: "Most played",
      meta: "Your top plays",
      icon: Flame,
      tile: "bg-amber-500/15 text-amber-300",
      open: () => {
        setLibraryTab("songs");
        setSongFilter("all");
        setSongSort("play-count");
        setView("library");
      },
      play: () => playIds("Most played", mostPlayed),
    },
    {
      key: "new",
      label: "New music",
      meta: "Just added",
      icon: Disc3,
      tile: "bg-violet-500/15 text-violet-300",
      open: () => {
        setLibraryTab("songs");
        setSongFilter("all");
        setSongSort("date-added");
        setView("library");
      },
      play: () => playIds("New music", newMusic),
    },
    {
      key: "discover",
      label: "Discovery",
      meta: "Fresh finds",
      icon: Compass,
      tile: "bg-sky-400/15 text-sky-300",
      open: () => setView("explore"),
      play: () => playIds("Discovery mix", DISCOVER_MIX),
    },
    {
      key: "saved",
      label: "Saved",
      meta: `${saved.length} downloads`,
      icon: ArrowDownToLine,
      tile: "bg-teal-500/15 text-teal-300",
      open: () => {
        setLibraryTab("songs");
        setSongFilter("saved");
        setView("library");
      },
      play: () => playIds("Saved songs", saved),
    },
    {
      key: "cached",
      label: "Cached",
      meta: `${cachedIds.length} songs`,
      icon: CloudDownload,
      tile: "bg-rose-500/15 text-rose-300",
      open: () => {
        setLibraryTab("songs");
        setSongFilter("cached");
        setView("library");
      },
      play: () => playIds("Cached songs", cachedIds),
    },
  ];

  return (
    <Rail label="Quick access">
      {cards.map((c) => {
        const Icon = c.icon;
        return (
          <div
            key={c.key}
            className={cn(
              "group relative h-36 w-36 shrink-0 snap-start overflow-hidden rounded-2xl transition md:w-auto md:snap-none",
              c.solid
                ? "bg-gradient-to-br from-primary/55 via-primary/22 to-transparent"
                : "bg-wav-surface hover:bg-accent",
            )}
          >
            <button
              onClick={c.open}
              className="flex h-full w-full flex-col justify-between p-3 text-left"
              aria-label={`Open ${c.label}`}
            >
              <span className={cn("flex h-9 w-9 items-center justify-center rounded-xl", c.tile)}>
                <Icon className={cn("h-[18px] w-[18px]", c.solid && "fill-current")} />
              </span>
              <span className="block pr-9">
                <span className="block text-[13px] font-bold leading-tight">{c.label}</span>
                <span
                  className={cn(
                    "mt-0.5 block text-[10px] text-muted-foreground",
                    c.solid && "text-foreground/70",
                  )}
                >
                  {c.meta}
                </span>
              </span>
            </button>
            <span
              role="button"
              tabIndex={0}
              onClick={(e) => {
                e.stopPropagation();
                c.play();
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.stopPropagation();
                  c.play();
                }
              }}
              className="absolute right-2.5 bottom-2.5 flex h-9 w-9 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-all hover:scale-105 focus-visible:opacity-100 active:scale-95 md:opacity-0 md:group-hover:opacity-100"
              aria-label={`Play ${c.label}`}
            >
              <Play className="ml-0.5 h-4 w-4 fill-primary-foreground" />
            </span>
          </div>
        );
      })}
    </Rail>
  );
}

/* ---------------------------------------------------------------- */
/* OFFLINE world — cached streaming songs still play & can be saved  */
/* ---------------------------------------------------------------- */
function OfflineCachedSection() {
  const playContext = useWavely((s) => s.playContext);
  const cachedIds = useWavely((s) => s.cachedIds);
  const cachedTracks = useMemo(
    () => cachedIds.map((id) => trackById.get(id)!).filter(Boolean),
    [cachedIds],
  );

  return (
    <section className="space-y-2">
      <div className="flex items-center gap-2.5 rounded-xl bg-amber-500/10 px-3.5 py-2.5 text-[13px] text-amber-300/90">
        <CloudOff className="h-4 w-4 shrink-0" />
        <p>
          Online discovery is hidden while you&apos;re offline. Songs cached from streaming below
          still play — and can be saved instantly.
        </p>
      </div>
      {cachedTracks.length > 0 && (
        <div className="rounded-2xl bg-wav-surface/50 p-1.5">
          <p className="px-2 pb-1 pt-2 text-[10px] font-bold uppercase tracking-widest text-emerald-300">
            Cached from streaming — {cachedTracks.length} song{cachedTracks.length > 1 ? "s" : ""}
          </p>
          {cachedTracks.map((t, i) => (
            <SongRow
              key={t.id}
              track={t}
              index={i}
              compact
              onPlay={() => playContext("Cached songs", cachedIds, i)}
            />
          ))}
        </div>
      )}
    </section>
  );
}

/* ---------------------------------------------------------------- */
/* New for you — online release timeline with a time-window switch   */
/* ---------------------------------------------------------------- */
function NewForYou() {
  const playContext = useWavely((s) => s.playContext);
  const currentTrack = useCurrentTrack();
  const [win, setWin] = useState<7 | 14 | 30>(7);

  const releases = useMemo(() => {
    const now = Date.now();
    return ALBUMS.filter(
      (a) => a.origin === "online" && a.releasedAt && now - a.releasedAt <= win * 86400000,
    ).sort((a, b) => {
      const fa = FOLLOWED_ARTIST_IDS.includes(a.artistId) ? 0 : 1;
      const fb = FOLLOWED_ARTIST_IDS.includes(b.artistId) ? 0 : 1;
      // followed artists first, then newest release wins
      return fa !== fb ? fa - fb : (b.releasedAt ?? 0) - (a.releasedAt ?? 0);
    });
  }, [win]);

  return (
    <section>
      <div className="mb-2 flex items-center justify-between gap-3">
        <h3 className="text-sm font-bold text-muted-foreground">New for you</h3>
        <Segmented
          ariaLabel="New release time window"
          value={win}
          onChange={setWin}
          options={[
            { value: 7, label: "1 week" },
            { value: 14, label: "2 weeks" },
            { value: 30, label: "1 month" },
          ]}
        />
      </div>
      {releases.length === 0 ? (
        <p className="rounded-xl bg-wav-surface/60 px-4 py-3 text-xs text-muted-foreground">
          Nothing dropped in this window — try 1 month
        </p>
      ) : (
        <Rail label="New releases">
          {releases.map((a) => (
            <ReleaseCard
              key={a.id}
              fluid
              cover={a.cover}
              title={a.title}
              meta={`${a.artist} • ${fmtAge(a.releasedAt!)}`}
              playing={currentTrack?.albumId === a.id}
              onPlay={() =>
                playContext(
                  a.title,
                  TRACKS.filter((t) => t.albumId === a.id).map((t) => t.id),
                  0,
                )
              }
            />
          ))}
        </Rail>
      )}
    </section>
  );
}

/* ---------------------------------------------------------------- */
/* Daily mixes — top genres rebuilt as AI-style radios               */
/* ---------------------------------------------------------------- */
function DailyMixes() {
  const playContext = useWavely((s) => s.playContext);

  const mixes = useMemo(() => {
    // top 3 genres by summed playCount across the whole catalogue (local + online)
    const playsByGenre = new Map<string, number>();
    for (const t of TRACKS) playsByGenre.set(t.genre, (playsByGenre.get(t.genre) ?? 0) + t.playCount);
    const topGenres = [...playsByGenre.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([genre]) => genre);
    return topGenres.map((genre, i) => {
      const mix = TRACKS.filter((t) => t.genre === genre)
        .sort((a, b) => b.playCount - a.playCount)
        .slice(0, 8);
      return {
        name: `Daily Mix ${i + 1}`,
        ids: mix.map((t) => t.id),
        // cover = album of the genre's most-played track (mix is sorted by plays)
        cover: albumCover(mix[0]?.albumId ?? ""),
        meta: `${genre} • ${mix.length} songs`,
      };
    });
  }, []);

  return (
    <section>
      <div className="mb-2 flex items-center justify-between">
        <h3 className="text-sm font-bold text-muted-foreground">Daily mixes</h3>
        <span className="inline-flex items-center gap-1 text-[10px] font-bold uppercase tracking-widest text-primary">
          <Sparkles className="h-3 w-3" /> AI-built
        </span>
      </div>
      <Rail label="Daily mixes">
        {mixes.map((m) => (
          <ReleaseCard
            key={m.name}
            fluid
            cover={m.cover}
            title={m.name}
            meta={m.meta}
            badge="ai"
            onPlay={() => playContext(m.name, m.ids, Math.floor(Math.random() * m.ids.length))}
          />
        ))}
      </Rail>
    </section>
  );
}

/* ---------------------------------------------------------------- */
/* Made for you — Wavely Weekly + AI DJ (was part of ExploreSection)  */
/* ---------------------------------------------------------------- */
const DISCOVER_MIX = ["t01", "t35", "t13", "t43", "t26", "t39", "t09", "t31", "t22", "t17"];

function MadeForYou() {
  const playContext = useWavely((s) => s.playContext);
  const setView = useWavely((s) => s.setView);

  return (
    <section>
      <h3 className="mb-2 text-sm font-bold text-muted-foreground">Made for you</h3>
      {/* mobile / tablet: wide banner cards */}
      <div className="no-scrollbar -mx-4 flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-1 md:hidden">
        <CuratedCard
          image="/wavely/curated-1.png"
          badge="ai"
          title="Wavely Weekly"
          subtitle="Fresh picks built from what you play — updated every Monday."
          onPlay={() => playContext("Wavely Weekly", DISCOVER_MIX, 0)}
        />
        <CuratedCard
          badge="ai"
          title="Wavely AI DJ"
          subtitle="Ask for a playlist, song facts, or just say “surprise me”."
          onPlay={() => setView("ai")}
        />
      </div>
      {/* desktop: compact Spotify-style cards (smaller than any hero, play on hover) */}
      <div className="hidden gap-3 md:grid md:grid-cols-[repeat(auto-fill,minmax(150px,1fr))]">
        <ReleaseCard
          fluid
          cover="/wavely/curated-1.png"
          badge="ai"
          title="Wavely Weekly"
          meta="Fresh Monday picks"
          onPlay={() => playContext("Wavely Weekly", DISCOVER_MIX, 0)}
        />
        <ReleaseCard
          fluid
          badge="ai"
          title="Wavely AI DJ"
          meta="Ask, discover, be surprised"
          onPlay={() => setView("ai")}
        />
      </div>
    </section>
  );
}

/* ---------------------------------------------------------------- */
/* Moods & moments — genre radios that also work offline             */
/* ---------------------------------------------------------------- */
const MOOD_ICONS: Record<MoodDef["id"], LucideIcon> = {
  focus: Brain,
  workout: Dumbbell,
  drive: Car,
  chill: Coffee,
  party: PartyPopper,
  tehran: MoonStar,
};

const MOOD_TINTS = [
  "bg-primary/12 text-primary",
  "bg-amber-500/12 text-amber-300",
  "bg-teal-500/12 text-teal-300",
  "bg-rose-500/12 text-rose-300",
  "bg-violet-500/12 text-violet-300",
  "bg-sky-400/12 text-sky-300",
];

function MoodsRow() {
  const isOffline = useWavely((s) => s.isOffline);
  const playContext = useWavely((s) => s.playContext);
  const { toast } = useToast();

  // playable song count per mood (offline shrinks the pool to local/downloaded)
  const counts = useMemo(() => {
    const out: Record<string, number> = {};
    for (const m of MOODS) {
      const candidates = TRACKS.filter((t) => m.genres.includes(t.genre));
      out[m.id] = isOffline
        ? candidates.filter((t) => t.origin === "local" || t.downloaded).length
        : candidates.length;
    }
    return out;
  }, [isOffline]);

  const playMood = (mood: MoodDef) => {
    let ids = TRACKS.filter((t) => mood.genres.includes(t.genre));
    if (isOffline) ids = ids.filter((t) => t.origin === "local" || t.downloaded);
    if (ids.length === 0) {
      toast({ description: "This mood needs online tracks" });
      return;
    }
    playContext(mood.label, ids.map((t) => t.id), Math.floor(Math.random() * ids.length));
  };

  return (
    <section>
      <h3 className="mb-2 text-sm font-bold text-muted-foreground">Moods & moments</h3>
      <div className="no-scrollbar -mx-4 flex snap-x gap-2.5 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
        {MOODS.map((mood, i) => {
          const Icon = MOOD_ICONS[mood.id];
          return (
            <button
              key={mood.id}
              onClick={() => playMood(mood)}
              className="flex shrink-0 snap-start items-center gap-2.5 rounded-2xl bg-wav-surface px-4 py-3 transition hover:bg-accent active:scale-[0.98]"
              aria-label={`Play the ${mood.label} mood`}
            >
              <span
                className={cn(
                  "flex h-10 w-10 shrink-0 items-center justify-center rounded-xl",
                  MOOD_TINTS[i % MOOD_TINTS.length],
                )}
              >
                <Icon className="h-5 w-5" />
              </span>
              <span className="min-w-0 text-left">
                <span className="block whitespace-nowrap text-xs font-bold">{mood.label}</span>
                <span className="block whitespace-nowrap text-[10px] text-muted-foreground">
                  {counts[mood.id] ?? 0} songs
                </span>
              </span>
            </button>
          );
        })}
      </div>
    </section>
  );
}

/* ---------------------------------------------------------------- */
/* Charts — deterministic simulated ranking per week / month         */
/* ---------------------------------------------------------------- */
function ChartsSection() {
  const playContext = useWavely((s) => s.playContext);
  const [period, setPeriod] = useState<"week" | "month">("week");

  const top5 = useMemo(() => {
    const bucket = period === "week" ? 604800000 : 2592000000;
    const slot = Math.floor(Date.now() / bucket);
    return TRACKS.filter((t) => t.origin === "online")
      .map((t) => {
        // stable pseudo-random bump per period — same ranking all week/month
        const seed = `${t.id}:${period}:${slot}`;
        let h = 0;
        for (const c of seed) h = (h * 31 + c.charCodeAt(0)) >>> 0;
        return { t, score: t.playCount + (h % 37) };
      })
      .sort((a, b) => b.score - a.score)
      .slice(0, 5);
  }, [period]);

  return (
    <section>
      <div className="mb-2 flex items-center justify-between gap-3">
        <h3 className="text-sm font-bold text-muted-foreground">Top streaming</h3>
        <Segmented
          ariaLabel="Chart period"
          value={period}
          onChange={setPeriod}
          options={[
            { value: "week", label: "This week" },
            { value: "month", label: "This month" },
          ]}
        />
      </div>
      <div className="rounded-2xl bg-wav-surface/50 p-1.5">
        {top5.map(({ t }, i) => (
          <div key={t.id} className="flex items-center gap-3">
            <span
              className={cn(
                "w-6 shrink-0 text-center font-display text-lg font-extrabold tabular-nums",
                i === 0 ? "text-primary" : "text-muted-foreground",
              )}
              aria-hidden="true"
            >
              {i + 1}
            </span>
            <SongRow
              track={t}
              compact
              onPlay={() =>
                playContext(
                  period === "week" ? "Top streaming · this week" : "Top streaming · this month",
                  top5.map((x) => x.t.id),
                  i,
                )
              }
            />
          </div>
        ))}
      </div>
    </section>
  );
}

/* ---------------------------------------------------------------- */
/* Recent artists — from listening history, backfilled by plays      */
/* ---------------------------------------------------------------- */
function RecentArtists() {
  const history = useWavely((s) => s.history);
  const playContext = useWavely((s) => s.playContext);

  const artists = useMemo(() => {
    const picked: Artist[] = [];
    const seen = new Set<string>();
    // unique artists in most-recent-first history order
    for (const id of history) {
      const t = trackById.get(id);
      if (!t || seen.has(t.artistId)) continue;
      const a = artistById.get(t.artistId);
      if (a) {
        seen.add(a.id);
        picked.push(a);
        if (picked.length >= 8) return picked;
      }
    }
    // thin history → backfill with the most-played artists not picked yet
    if (picked.length < 4) {
      const byPlays = ARTISTS.filter((a) => !seen.has(a.id))
        .map((a) => ({ a, plays: tracksOfArtist(a.id).reduce((sum, t) => sum + t.playCount, 0) }))
        .sort((x, y) => y.plays - x.plays);
      for (const { a } of byPlays) {
        picked.push(a);
        if (picked.length >= 8) break;
      }
    }
    return picked;
  }, [history]);

  return (
    <section>
      <h3 className="mb-2 text-sm font-bold text-muted-foreground">Recent artists</h3>
      <div className="no-scrollbar -mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
        {artists.map((a) => (
          <button
            key={a.id}
            onClick={() => playContext(a.name, tracksOfArtist(a.id).map((t) => t.id), 0)}
            className="flex w-20 shrink-0 snap-start flex-col items-center gap-1.5"
            aria-label={`Play ${a.name}`}
          >
            <span className="relative block h-16 w-16 overflow-hidden rounded-full ring-1 ring-border transition hover:ring-2 hover:ring-primary">
              <Image src={a.image} alt="" fill sizes="64px" className="object-cover" />
            </span>
            <span className="w-full truncate text-center text-[11px] text-muted-foreground">
              {a.name}
            </span>
          </button>
        ))}
      </div>
    </section>
  );
}

/* ---------------------------------------------------------------- */
/* Home view                                                         */
/* ---------------------------------------------------------------- */
export function HomeView() {
  const setView = useWavely((s) => s.setView);
  const isOffline = useWavely((s) => s.isOffline);

  return (
    <div className="mx-auto w-full space-y-6 px-4 pb-10 md:max-w-3xl md:px-8 lg:max-w-5xl">
      <HomeHeader />

      <OfflineBanner />

      {/* swipeable quick access — liked · most played · new · discovery · saved · cached */}
      <QuickAccessRow />

      {/* offline: cached streaming songs stay playable (replaces online discovery) */}
      {isOffline && <OfflineCachedSection />}

      {/* online world — Spotify style */}
      {!isOffline && <NewForYou />}
      {!isOffline && <DailyMixes />}
      {!isOffline && <MadeForYou />}

      {/* works offline — moods fall back to local/downloaded files */}
      <MoodsRow />

      {!isOffline && <ChartsSection />}

      {/* works offline — recent artists from local listening history */}
      <RecentArtists />

      {/* AI DJ strip (desktop) */}
      {!isOffline && (
        <button
          onClick={() => setView("ai")}
          className="group hidden w-full items-center gap-4 overflow-hidden rounded-2xl bg-gradient-to-r from-primary/25 via-primary/10 to-transparent p-5 text-left transition hover:from-primary/35 md:flex"
        >
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-primary text-primary-foreground shadow-lg accent-glow">
            <Sparkles className="h-5 w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="font-display text-base font-bold">Wavely AI DJ</h3>
            <p className="truncate text-sm text-muted-foreground">
              Your assistant lives in the navbar — playlists, trivia, discoveries.
            </p>
          </div>
          <ArrowRight className="h-5 w-5 shrink-0 text-primary transition-transform group-hover:translate-x-1" />
        </button>
      )}

      <footer className="flex flex-wrap items-center justify-center gap-x-2 gap-y-1 pb-2 pt-2 text-center text-xs text-muted-foreground">
        Wavely prototype • Musicolet UX × Spotify design • v1.0.3-preview
      </footer>
    </div>
  );
}
