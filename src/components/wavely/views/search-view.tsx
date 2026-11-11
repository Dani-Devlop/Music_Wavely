"use client";

import Image from "next/image";
import { useMemo, useState } from "react";
import { SongRow } from "../song-row";
import { EqBars } from "../eq-bars";
import { SourceModeChips } from "../source-mode-chips";
import { SectionHead } from "../cards";
import { useWavely, useCurrentTrack, useEffectiveMode, filterByMode, albumMatchesMode, artistMatchesMode, playlistMatchesMode } from "@/lib/wavely/store";
import { ALBUMS, ARTISTS, PLAYLISTS, TRACKS, albumCover, tracksOfAlbum } from "@/lib/wavely/data";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";
import {
  Search,
  X,
  Music2,
  UserRound,
  ListPlus,
  MicVocal,
  WifiOff,
  Podcast,
  Play,
  ArrowLeft,
  Sparkles,
} from "lucide-react";
import { cn } from "@/lib/utils";

type Filter = "all" | "songs" | "albums" | "artists" | "playlists";

const FILTERS: { id: Filter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "songs", label: "Songs" },
  { id: "albums", label: "Albums" },
  { id: "artists", label: "Artists" },
  { id: "playlists", label: "Playlists" },
];

/* Spotify page 7/13 browse chips — filter the big category cards */
type BrowseChip = "all" | "music" | "podcast";

const BROWSE_CHIPS: { id: BrowseChip; label: string; icon: React.ElementType }[] = [
  { id: "all", label: "All", icon: Sparkles },
  { id: "music", label: "Music", icon: Music2 },
  { id: "podcast", label: "Podcasts", icon: Podcast },
];

const BROWSE_GENRES = [
  "Synthwave", "Synthpop", "Electronic", "Dream Pop", "Lo-Fi",
  "Rock", "Pop", "Indie Folk", "World", "Alternative",
];
const GENRE_HUES = [
  "bg-emerald-800", "bg-teal-800", "bg-lime-800", "bg-green-900",
  "bg-emerald-700", "bg-teal-700", "bg-lime-900", "bg-green-800",
  "bg-emerald-900", "bg-teal-900",
];

interface BrowseCat {
  id: string;
  label: string;
  kind: "music" | "podcast";
  /** solid Spotify-style card colour */
  tint: string;
  /** artwork bleeding off the tilted corner */
  art: string;
  hint: string;
  open: () => void;
}

/** Prototype podcast catalogue — the full player ships with the Flutter build. */
const PODCASTS = [
  { id: "p1", name: "Radio Wavely", desc: "Weekly music news & fresh drops", eps: 42, cover: "/covers/insta-2.png" },
  { id: "p2", name: "Synth Dreams FM", desc: "Synthwave & retrowave deep cuts", eps: 18, cover: "/covers/online-chrome-city.png" },
  { id: "p3", name: "Tehran Nights", desc: "Stories & sounds from the city", eps: 27, cover: "/covers/persian-echoes.png" },
  { id: "p4", name: "Lo-Fi Study Room", desc: "Beats to focus & study to", eps: 64, cover: "/covers/deep-focus.png" },
  { id: "p5", name: "Vinyl Stories", desc: "Artists on the records that made them", eps: 12, cover: "/covers/paper-planes.png" },
  { id: "p6", name: "Indie Spotlight", desc: "Rising artists, tiny-stage energy", eps: 9, cover: "/covers/insta-5.png" },
];

export function SearchView() {
  const [q, setQ] = useState("");
  const [filter, setFilter] = useState<Filter>("all");
  const [browseChip, setBrowseChip] = useState<BrowseChip>("all");
  const [pane, setPane] = useState<"genres" | "podcasts" | null>(null);
  const { toast } = useToast();
  const playContext = useWavely((s) => s.playContext);
  const setLibraryTab = useWavely((s) => s.setLibraryTab);
  const setView = useWavely((s) => s.setView);
  const current = useCurrentTrack();
  const mode = useEffectiveMode();
  const isOffline = useWavely((s) => s.isOffline);

  const query = q.trim().toLowerCase();

  const results = useMemo(() => {
    if (!query) return null;
    const songs = filterByMode(
      TRACKS.filter((t) => (t.title + " " + t.artist + " " + t.album).toLowerCase().includes(query)),
      mode,
    );
    const albums = ALBUMS.filter((a) => {
      if (!albumMatchesMode(a, mode)) return false;
      return (a.title + " " + a.artist).toLowerCase().includes(query);
    });
    const artists = ARTISTS.filter((a) => {
      const artistAlbums = a.albumIds.map((id) => ALBUMS.find((x) => x.id === id)!);
      if (!artistMatchesMode(artistAlbums, mode)) return false;
      return a.name.toLowerCase().includes(query);
    });
    const playlists = PLAYLISTS.filter((p) => {
      if (!playlistMatchesMode(p, mode)) return false;
      return (p.name + " " + p.description).toLowerCase().includes(query);
    });
    return { songs, albums, artists, playlists };
  }, [query, mode]);

  const hasResults = results && (results.songs.length || results.albums.length || results.artists.length || results.playlists.length);

  /* Spotify page 13: one "Top result" hero above the songs list.
     Priority: exact song title → exact artist → exact album → first song. */
  const topResult = useMemo(() => {
    if (!results || !hasResults) return null;
    const songResult = (song: (typeof results.songs)[number]) => {
      const ids = results.songs.map((x) => x.id);
      return {
        kind: "Song",
        title: song.title,
        sub: song.artist,
        img: albumCover(song.albumId),
        round: false,
        onPlay: () => playContext(`Search: ${query}`, ids, results.songs.indexOf(song)),
      };
    };
    const exactSong = results.songs.find((t) => t.title.toLowerCase().startsWith(query));
    if (exactSong) return songResult(exactSong);
    const exactArtist = results.artists.find((a) => a.name.toLowerCase().startsWith(query));
    if (exactArtist) {
      return {
        kind: "Artist",
        title: exactArtist.name,
        sub: "Artist",
        img: exactArtist.image,
        round: true,
        onPlay: () =>
          playContext(exactArtist.name, TRACKS.filter((t) => t.artistId === exactArtist.id).map((t) => t.id), 0),
      };
    }
    const exactAlbum = results.albums.find((a) => a.title.toLowerCase().startsWith(query));
    if (exactAlbum) {
      return {
        kind: "Album",
        title: exactAlbum.title,
        sub: exactAlbum.artist,
        img: exactAlbum.cover,
        round: false,
        onPlay: () => playContext(exactAlbum.title, tracksOfAlbum(exactAlbum.id).map((t) => t.id), 0),
      };
    }
    return results.songs[0] ? songResult(results.songs[0]) : null;
  }, [results, hasResults, query, playContext]);

  /* big colourful browse categories — chips filter them (Spotify p7) */
  const categories = useMemo<BrowseCat[]>(() => {
    const goGenres = () => setPane("genres");
    const goPodcasts = () => setPane("podcasts");
    return [
      {
        id: "music",
        label: "Music",
        kind: "music",
        tint: "bg-emerald-600",
        art: "/moods/party.png",
        hint: "Your library + streaming",
        open: goGenres,
      },
      {
        id: "podcasts",
        label: "Podcasts",
        kind: "podcast",
        tint: "bg-violet-600",
        art: "/moods/focus.png",
        hint: "Shows & episodes",
        open: goPodcasts,
      },
      {
        id: "made",
        label: "Made for you",
        kind: "music",
        tint: "bg-rose-600",
        art: "/wavely/curated-1.png",
        hint: "Weekly mixes & AI DJ",
        open: () => setView("home"),
      },
      {
        id: "new",
        label: "New releases",
        kind: "music",
        tint: "bg-amber-500",
        art: "/covers/online-chrome-city.png",
        hint: "Fresh from artists you follow",
        open: () => setView("explore"),
      },
      {
        id: "charts",
        label: "Charts",
        kind: "music",
        tint: "bg-fuchsia-600",
        art: "/covers/insta-1.png",
        hint: "Top players this week",
        open: () => setView("explore"),
      },
      {
        id: "discover",
        label: "Discover",
        kind: "music",
        tint: "bg-teal-600",
        art: "/covers/insta-3.png",
        hint: "Fresh finds beyond your lanes",
        open: () => setView("explore"),
      },
      {
        id: "persian",
        label: "Persian & World",
        kind: "music",
        tint: "bg-orange-600",
        art: "/covers/persian-echoes.png",
        hint: "Home, in melodies",
        open: () => {
          const pl = PLAYLISTS.find((p) => p.id === "pl3");
          if (pl) playContext(pl.name, pl.trackIds, 0);
        },
      },
      {
        id: "live",
        label: "Live events",
        kind: "podcast",
        tint: "bg-red-600",
        art: "/moods/workout.png",
        hint: "Concerts near you",
        open: () => toast({ description: "Live events land with the Flutter build" }),
      },
    ].filter((c) => browseChip === "all" || c.kind === browseChip);
  }, [browseChip, playContext, setView, toast]);

  return (
    <div className="mx-auto max-w-6xl space-y-6 px-4 pb-8 pt-6 md:px-6">
      {/* sticky search + source chips */}
      <div className="sticky top-0 z-20 -mx-4 bg-background/85 px-4 pb-3 pt-2 backdrop-blur-xl md:-mx-6 md:px-6">
        <div className="relative">
          <Search className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={isOffline ? "Search your music…" : "Search music…"}
            className="h-12 rounded-full border-border bg-secondary pl-11 pr-10 text-base"
            aria-label="Search music"
          />
          {q && (
            <button
              onClick={() => setQ("")}
              className="absolute right-3 top-1/2 -translate-y-1/2 rounded-full p-1.5 text-muted-foreground hover:bg-accent hover:text-foreground"
              aria-label="Clear search"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
        <SourceModeChips className="mt-3" />
        {isOffline && (
          <p className="mt-2 flex items-center gap-1.5 text-xs text-amber-400/90">
            <WifiOff className="h-3 w-3" /> Offline — searching on-device music only
          </p>
        )}
      </div>

      {query && (
        <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 md:mx-0 md:px-0">
          {FILTERS.map((f) => (
            <button
              key={f.id}
              onClick={() => setFilter(f.id)}
              className={cn(
                "shrink-0 rounded-full px-4 py-1.5 text-sm font-medium transition",
                filter === f.id ? "bg-primary text-primary-foreground" : "bg-secondary hover:bg-accent",
              )}
            >
              {f.label}
            </button>
          ))}
        </div>
      )}

      {query && hasResults ? (
        <div className="space-y-8">
          {/* Spotify p13 — Top result hero + Songs side by side (desktop) */}
          {filter === "all" && topResult && (
            <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.6fr)]">
              <section>
                <SectionHead size="md" title="Top result" />
                <div className="group relative overflow-hidden rounded-2xl bg-wav-surface p-5 transition hover:bg-accent">
                  <div className="flex items-start gap-4">
                    <div className={cn("relative h-24 w-24 shrink-0 overflow-hidden shadow-lg", topResult.round ? "rounded-full" : "rounded-xl")}>
                      <Image src={topResult.img} alt={topResult.title} fill sizes="96px" className="object-cover" />
                    </div>
                    <div className="min-w-0 flex-1 pr-16 pt-1">
                      <p className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground">
                        {topResult.kind}
                      </p>
                      <h3 className="mt-1 truncate font-display text-2xl font-extrabold tracking-tight">
                        {topResult.title}
                      </h3>
                      <p className="mt-1 truncate text-xs text-muted-foreground">{topResult.sub}</p>
                    </div>
                  </div>
                  <span className="absolute bottom-4 right-4 flex h-12 w-12 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform hover:scale-105 active:scale-95">
                    <button onClick={topResult.onPlay} aria-label={`Play ${topResult.title}`} className="flex h-full w-full items-center justify-center">
                      <Play className="ml-0.5 h-5 w-5 fill-primary-foreground" />
                    </button>
                  </span>
                </div>
              </section>
              {(filter === "all" || filter === "songs") && results!.songs.length > 0 && (
                <section>
                  <SectionHead size="md" title="Songs" hint={`${results!.songs.length} match${results!.songs.length > 1 ? "es" : ""}`} />
                  <div className="space-y-0.5">
                    {results!.songs.slice(0, 4).map((t) => (
                      <SongRow
                        key={t.id}
                        track={t}
                        hideOriginChip
                        onPlay={() => playContext(`Search: ${query}`, results!.songs.map((x) => x.id), results!.songs.indexOf(t))}
                      />
                    ))}
                  </div>
                </section>
              )}
            </div>
          )}

          {!(filter === "all" && topResult) && (filter === "all" || filter === "songs") && results!.songs.length > 0 && (
            <section>
              <SectionHead size="md" title="Songs" hint={`${results!.songs.length} match${results!.songs.length > 1 ? "es" : ""}`} />
              <div className="space-y-0.5">
                {results!.songs.map((t, i) => (
                  <SongRow
                    key={t.id}
                    track={t}
                    hideOriginChip
                    onPlay={() => playContext(`Search: ${query}`, results!.songs.map((x) => x.id), i)}
                  />
                ))}
              </div>
            </section>
          )}
          {(filter === "all" || filter === "albums") && results!.albums.length > 0 && (
            <section>
              <SectionHead size="md" title="Albums" />
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                {results!.albums.map((a) => (
                  <button key={a.id} onClick={() => playContext(a.title, tracksOfAlbum(a.id).map((t) => t.id), 0)} className="rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent">
                    <div className="relative mb-2 aspect-square overflow-hidden rounded-lg">
                      <Image src={a.cover} alt={a.title} fill sizes="200px" className="object-cover" />
                    </div>
                    <p className="truncate text-sm font-semibold">{a.title}</p>
                    <p className="truncate text-xs text-muted-foreground">{a.artist} • {a.year}</p>
                  </button>
                ))}
              </div>
            </section>
          )}
          {(filter === "all" || filter === "artists") && results!.artists.length > 0 && (
            <section>
              <SectionHead size="md" title="Artists" />
              <div className="flex flex-wrap gap-4">
                {results!.artists.map((a) => (
                  <button key={a.id} onClick={() => playContext(a.name, TRACKS.filter((t) => t.artistId === a.id).map((t) => t.id), 0)} className="w-24 text-center">
                    <div className="relative mx-auto mb-2 h-20 w-20 overflow-hidden rounded-full">
                      <Image src={a.image} alt={a.name} fill sizes="80px" className="object-cover" />
                    </div>
                    <p className="truncate text-xs font-medium">{a.name}</p>
                  </button>
                ))}
              </div>
            </section>
          )}
          {(filter === "all" || filter === "playlists") && results!.playlists.length > 0 && (
            <section>
              <SectionHead size="md" title="Playlists" />
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                {results!.playlists.map((p) => (
                  <button key={p.id} onClick={() => playContext(p.name, p.trackIds, 0)} className="rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent">
                    <div className="relative mb-2 flex h-24 items-center justify-center rounded-lg bg-gradient-to-br from-primary/40 to-primary/5">
                      <ListPlus className="h-8 w-8 text-primary" />
                    </div>
                    <p className="truncate text-sm font-semibold">{p.name}</p>
                    <p className="truncate text-xs text-muted-foreground">{p.trackIds.length} songs</p>
                  </button>
                ))}
              </div>
            </section>
          )}
        </div>
      ) : query && !hasResults ? (
        <div className="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-border py-16 text-muted-foreground">
          <Search className="h-8 w-8" />
          <p className="text-center text-sm">
            No results for “{q}”
            <span className="mt-1 block text-xs">Tip: try different words or a shorter query</span>
          </p>
        </div>
      ) : (
        <>
          <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <Search className="h-3 w-3" /> Type to search — switch chips above to narrow
          </p>

          {/* Spotify p7/13 — All / Music / Podcasts chips above Browse all */}
          {!pane && (
            <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 md:mx-0 md:px-0">
              {BROWSE_CHIPS.map((c) => {
                const Icon = c.icon;
                return (
                  <button
                    key={c.id}
                    onClick={() => setBrowseChip(c.id)}
                    aria-pressed={browseChip === c.id}
                    className={cn(
                      "flex h-9 shrink-0 items-center gap-1.5 rounded-full px-4 text-sm font-semibold transition",
                      browseChip === c.id
                        ? "bg-primary text-primary-foreground"
                        : "bg-secondary text-muted-foreground hover:bg-accent hover:text-foreground",
                    )}
                  >
                    <Icon className="h-3.5 w-3.5" />
                    {c.label}
                  </button>
                );
              })}
            </div>
          )}

          {pane ? (
            <>
              <button
                onClick={() => setPane(null)}
                className="flex items-center gap-1.5 rounded-full bg-secondary px-3.5 py-2 text-xs font-semibold text-muted-foreground transition hover:bg-accent hover:text-foreground"
                aria-label="Back to browse all"
              >
                <ArrowLeft className="h-3.5 w-3.5" /> Browse all
              </button>

              {pane === "genres" ? (
                <section>
                  <SectionHead title="Browse music" hint="Every genre in your world" />
                  <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                    {BROWSE_GENRES.map((g, i) => (
                      <button
                        key={g}
                        onClick={() => {
                          setLibraryTab("genres");
                          setView("library");
                        }}
                        className={cn(
                          "relative flex h-24 items-start overflow-hidden rounded-xl p-3 text-left text-sm font-bold text-white/95 transition hover:scale-[1.02]",
                          GENRE_HUES[i % GENRE_HUES.length],
                        )}
                      >
                        {g}
                        {current?.genre === g && (
                          <span className="absolute bottom-2 left-3"><EqBars barClassName="bg-white/90" /></span>
                        )}
                        <MicVocal className="absolute -bottom-3 -right-2 h-16 w-16 rotate-12 text-white/15" />
                      </button>
                    ))}
                  </div>
                </section>
              ) : (
                <section>
                  <SectionHead title="Podcasts" hint={`${PODCASTS.length} shows — player ships with the Flutter build`} />
                  <div className="grid gap-3 sm:grid-cols-2">
                    {PODCASTS.map((p) => (
                      <div key={p.id} className="flex items-center gap-3 rounded-2xl bg-wav-surface p-3 transition hover:bg-accent">
                        <div className="relative h-16 w-16 shrink-0 overflow-hidden rounded-lg">
                          <Image src={p.cover} alt={p.name} fill sizes="64px" className="object-cover" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-bold">{p.name}</p>
                          <p className="truncate text-xs text-muted-foreground">{p.desc}</p>
                          <p className="mt-1 inline-flex items-center gap-1 rounded-full bg-secondary px-2 py-0.5 text-[10px] font-bold text-muted-foreground">
                            <Podcast className="h-2.5 w-2.5" /> {p.eps} episodes
                          </p>
                        </div>
                        <button
                          onClick={() => toast({ description: `“${p.name}” starts playing in the Flutter build` })}
                          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground transition hover:scale-105 active:scale-95"
                          aria-label={`Play ${p.name}`}
                        >
                          <Play className="ml-0.5 h-4 w-4 fill-primary-foreground" />
                        </button>
                      </div>
                    ))}
                  </div>
                </section>
              )}
            </>
          ) : (
            <section>
              <SectionHead title="Browse all" hint="Jump into a category" />
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                {categories.map((c) => (
                  <button
                    key={c.id}
                    onClick={c.open}
                    className={cn(
                      "group relative h-32 overflow-hidden rounded-xl p-3.5 text-left transition hover:scale-[1.02] active:scale-[0.98]",
                      c.tint,
                    )}
                    aria-label={`Open ${c.label}`}
                  >
                    {/* tilted artwork bleeding off the corner (Spotify browse tiles) */}
                    <span
                      className="absolute bottom-0 right-0 h-[74%] aspect-square translate-x-[24%] translate-y-[24%] rotate-[22deg] overflow-hidden rounded-lg shadow-[0_6px_18px_rgba(0,0,0,0.45)] transition-transform duration-300 group-hover:scale-[1.06]"
                      aria-hidden
                    >
                      <Image src={c.art} alt="" fill sizes="(min-width: 768px) 220px, 45vw" className="object-cover" />
                    </span>
                    <span className="absolute inset-0 flex flex-col p-3.5">
                      <span className="text-lg font-extrabold leading-tight text-white drop-shadow-sm">
                        {c.label}
                      </span>
                      <span className="mt-auto text-[10px] font-semibold text-white/80">
                        {c.hint}
                      </span>
                    </span>
                  </button>
                ))}
              </div>
            </section>
          )}

          {mode === "online" && !pane && (
            <section>
              <SectionHead title="Fresh streams" hint="Just landed on your streaming sources" />
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                {ALBUMS.filter((a) => albumMatchesMode(a, "online")).map((a) => (
                  <button
                    key={a.id}
                    onClick={() => playContext(a.title, tracksOfAlbum(a.id).map((t) => t.id), 0)}
                    className="rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent"
                  >
                    <div className="relative mb-2 aspect-square overflow-hidden rounded-lg">
                      <Image src={a.cover} alt={a.title} fill sizes="200px" className="object-cover" />
                    </div>
                    <p className="truncate text-sm font-semibold">{a.title}</p>
                    <p className="truncate text-xs text-muted-foreground">{a.artist}</p>
                  </button>
                ))}
              </div>
            </section>
          )}
        </>
      )}
    </div>
  );
}
