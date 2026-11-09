"use client";

import Image from "next/image";
import { useMemo, useState } from "react";
import { SongRow } from "../song-row";
import { EqBars } from "../eq-bars";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import { ALBUMS, ARTISTS, PLAYLISTS, TRACKS, tracksOfAlbum } from "@/lib/wavely/data";
import { Input } from "@/components/ui/input";
import { Search, X, Music2, Disc3, UserRound, ListPlus, MicVocal } from "lucide-react";
import { cn } from "@/lib/utils";

type Filter = "all" | "songs" | "albums" | "artists" | "playlists";

const FILTERS: { id: Filter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "songs", label: "Songs" },
  { id: "albums", label: "Albums" },
  { id: "artists", label: "Artists" },
  { id: "playlists", label: "Playlists" },
];

const BROWSE_GENRES = ["Synthwave", "Electronic", "Lo-Fi", "Rock", "Pop", "Indie Folk", "World", "Alternative"];
const GENRE_HUES = [
  "bg-emerald-800", "bg-teal-800", "bg-lime-800", "bg-green-900",
  "bg-emerald-700", "bg-teal-700", "bg-lime-900", "bg-green-800",
];

export function SearchView() {
  const [q, setQ] = useState("");
  const [filter, setFilter] = useState<Filter>("all");
  const playContext = useWavely((s) => s.playContext);
  const setLibraryTab = useWavely((s) => s.setLibraryTab);
  const setView = useWavely((s) => s.setView);
  const current = useCurrentTrack();

  const query = q.trim().toLowerCase();
  const results = useMemo(() => {
    if (!query) return null;
    return {
      songs: TRACKS.filter((t) => (t.title + " " + t.artist + " " + t.album).toLowerCase().includes(query)),
      albums: ALBUMS.filter((a) => (a.title + " " + a.artist).toLowerCase().includes(query)),
      artists: ARTISTS.filter((a) => a.name.toLowerCase().includes(query)),
      playlists: PLAYLISTS.filter((p) => (p.name + " " + p.description).toLowerCase().includes(query)),
    };
  }, [query]);

  const hasResults = results && (results.songs.length || results.albums.length || results.artists.length || results.playlists.length);

  return (
    <div className="mx-auto max-w-6xl space-y-6 px-4 pb-8 pt-6 md:px-6">
      <div className="relative">
        <Search className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Songs, albums, artists…"
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
          {(filter === "all" || filter === "songs") && results!.songs.length > 0 && (
            <section>
              <h2 className="mb-2 flex items-center gap-2 font-display text-lg font-bold">
                <Music2 className="h-4 w-4 text-primary" /> Songs
              </h2>
              <div className="space-y-0.5">
                {results!.songs.map((t, i) => (
                  <SongRow
                    key={t.id}
                    track={t}
                    onPlay={() => playContext(`Search: ${query}`, results!.songs.map((x) => x.id), i)}
                  />
                ))}
              </div>
            </section>
          )}
          {(filter === "all" || filter === "albums") && results!.albums.length > 0 && (
            <section>
              <h2 className="mb-3 flex items-center gap-2 font-display text-lg font-bold">
                <Disc3 className="h-4 w-4 text-primary" /> Albums
              </h2>
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
              <h2 className="mb-3 flex items-center gap-2 font-display text-lg font-bold">
                <UserRound className="h-4 w-4 text-primary" /> Artists
              </h2>
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
              <h2 className="mb-3 flex items-center gap-2 font-display text-lg font-bold">
                <ListPlus className="h-4 w-4 text-primary" /> Playlists
              </h2>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                {results!.playlists.map((p) => (
                  <button key={p.id} onClick={() => playContext(p.name, p.trackIds, 0)} className="rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent">
                    <div className="mb-2 flex h-24 items-center justify-center rounded-lg bg-gradient-to-br from-primary/40 to-primary/5">
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
          <p className="text-sm">No results for “{q}”</p>
        </div>
      ) : (
        <section>
          <h2 className="mb-3 font-display text-xl font-bold">Browse all</h2>
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
      )}
    </div>
  );
}
