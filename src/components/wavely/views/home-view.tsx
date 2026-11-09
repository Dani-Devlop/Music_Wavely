"use client";

import Image from "next/image";
import { Cover } from "../cover";
import { EqBars } from "../eq-bars";
import { SongRow } from "../song-row";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import { ALBUMS, PLAYLISTS, albumById, trackById, tracksOfAlbum } from "@/lib/wavely/data";
import { Button } from "@/components/ui/button";
import { ArrowRight, Play, Sparkles, ListMusic } from "lucide-react";
import { cn } from "@/lib/utils";

function greeting(): string {
  const h = new Date().getHours();
  if (h < 5) return "Good night";
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  if (h < 22) return "Good evening";
  return "Good night";
}

function QuickTile({
  cover,
  title,
  onOpen,
  onPlay,
  playing,
}: {
  cover: string;
  title: string;
  onOpen: () => void;
  onPlay: () => void;
  playing?: boolean;
}) {
  return (
    <button
      onClick={onOpen}
      className="group relative flex items-center gap-3 overflow-hidden rounded-lg bg-wav-elevated/70 pr-2 text-left transition hover:bg-accent"
    >
      <Cover src={cover} alt={title} size={64} rounded="rounded-none" className="h-16 w-16" />
      <span className="min-w-0 flex-1 truncate text-sm font-semibold">{title}</span>
      <span
        role="button"
        tabIndex={0}
        aria-label={`Play ${title}`}
        onClick={(e) => {
          e.stopPropagation();
          onPlay();
        }}
        onKeyDown={(e) => e.key === "Enter" && e.stopPropagation()}
        className="mr-1 flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-lg transition-all hover:scale-105 hover:bg-wav-accent-hover group-hover:opacity-100 focus:opacity-100"
      >
        {playing ? <EqBars barClassName="bg-primary-foreground" /> : <Play className="h-4 w-4 fill-primary-foreground" />}
      </span>
    </button>
  );
}

function SectionHeader({ title, action }: { title: string; action?: React.ReactNode }) {
  return (
    <div className="mb-3 flex items-center justify-between">
      <h2 className="font-display text-xl font-bold tracking-tight md:text-2xl">{title}</h2>
      {action}
    </div>
  );
}

export function HomeView() {
  const playContext = useWavely((s) => s.playContext);
  const setView = useWavely((s) => s.setView);
  const currentTrack = useCurrentTrack();

  const recentAlbums = ALBUMS.slice(0, 6);
  const featuredTrack = trackById.get("t01")!;

  return (
    <div className="mx-auto max-w-6xl space-y-8 px-4 pb-8 pt-6 md:px-6">
      <div>
        <p className="text-sm text-muted-foreground">{greeting()}</p>
        <h1 className="font-display text-2xl font-bold tracking-tight md:text-3xl">Your library, your way</h1>
      </div>

      {/* Quick tiles — Spotify style */}
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-3">
        {recentAlbums.map((a) => (
          <QuickTile
            key={a.id}
            cover={a.cover}
            title={a.title}
            playing={currentTrack?.albumId === a.id}
            onOpen={() => {
              useWavely.getState().setLibraryTab("albums");
              setView("library");
            }}
            onPlay={() => {
              const tracks = tracksOfAlbum(a.id).map((t) => t.id);
              playContext(a.title, tracks, 0);
            }}
          />
        ))}
        {PLAYLISTS.slice(0, 3).map((p) => (
          <QuickTile
            key={p.id}
            cover={albumById.get(PLAYLISTS.indexOf(p) % 2 === 0 ? "al3" : "al7")?.cover ?? "/covers/green-circuit.png"}
            title={p.name}
            onOpen={() => {
              useWavely.getState().setLibraryTab("playlists");
              setView("library");
            }}
            onPlay={() => playContext(p.name, p.trackIds, 0)}
          />
        ))}
      </div>

      {/* AI DJ promo */}
      <button
        onClick={() => setView("ai")}
        className="group relative w-full overflow-hidden rounded-2xl bg-gradient-to-r from-primary/25 via-primary/10 to-transparent p-5 text-left transition hover:from-primary/35 md:p-6"
      >
        <div className="flex items-center gap-4">
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-primary text-primary-foreground shadow-lg accent-glow">
            <Sparkles className="h-6 w-6" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="font-display text-lg font-bold">Wavely AI DJ</h3>
            <p className="truncate text-sm text-muted-foreground">
              Ask for a playlist, song facts, or &quot;surprise me&quot; — your assistant lives in the navbar.
            </p>
          </div>
          <ArrowRight className="h-5 w-5 shrink-0 text-primary transition-transform group-hover:translate-x-1" />
        </div>
      </button>

      {/* Featured track */}
      <section>
        <SectionHeader title="Jump back in" />
        <div className="space-y-0.5">
          {["t01", "t17", "t26", "t31", "t13"].map((id, i) => {
            const t = trackById.get(id)!;
            return (
              <SongRow
                key={id}
                track={t}
                index={i}
                showIndex
                onPlay={() => playContext("Jump back in", ["t01", "t17", "t26", "t31", "t13"], i)}
              />
            );
          })}
        </div>
      </section>

      {/* Made for you */}
      <section>
        <SectionHeader
          title="Made for you"
          action={
            <Button variant="ghost" size="sm" className="text-xs text-muted-foreground" onClick={() => { useWavely.getState().setLibraryTab("playlists"); setView("library"); }}>
              Show all
            </Button>
          }
        />
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
          {PLAYLISTS.map((p) => (
            <button
              key={p.id}
              onClick={() => playContext(p.name, p.trackIds, 0)}
              className="group rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent"
            >
              <div className="relative mb-3 aspect-square overflow-hidden rounded-lg bg-secondary">
                <Image
                  src={albumById.get(p.trackIds[0] === "t17" ? "al5" : p.trackIds[0] === "t31" ? "al8" : p.trackIds[0] === "t22" ? "al6" : "al3")?.cover ?? "/covers/neon-horizon.png"}
                  alt={p.name}
                  fill
                  sizes="(max-width: 640px) 45vw, 220px"
                  className="object-cover"
                />
                <span className="absolute bottom-2 right-2 flex h-11 w-11 translate-y-2 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-xl transition-all group-hover:translate-y-0 group-hover:opacity-100">
                  <Play className="h-5 w-5 fill-primary-foreground" />
                </span>
              </div>
              <p className="truncate text-sm font-semibold">{p.name}</p>
              <p className="truncate text-xs text-muted-foreground">{p.description}</p>
            </button>
          ))}
        </div>
      </section>

      {/* New releases */}
      <section>
        <SectionHeader title="New releases" />
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
          {[...ALBUMS].sort((a, b) => b.year - a.year).slice(0, 5).map((a) => (
            <button
              key={a.id}
              onClick={() => playContext(a.title, tracksOfAlbum(a.id).map((t) => t.id), 0)}
              className="group rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent"
            >
              <div className="relative mb-3 aspect-square overflow-hidden rounded-lg bg-secondary">
                <Image src={a.cover} alt={a.title} fill sizes="(max-width: 640px) 45vw, 220px" className="object-cover" />
                <span className="absolute bottom-2 right-2 flex h-11 w-11 translate-y-2 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-xl transition-all group-hover:translate-y-0 group-hover:opacity-100">
                  <Play className="h-5 w-5 fill-primary-foreground" />
                </span>
              </div>
              <p className="truncate text-sm font-semibold">{a.title}</p>
              <p className="truncate text-xs text-muted-foreground">{a.year} • {a.artist}</p>
            </button>
          ))}
        </div>
      </section>

      {/* Your top genres */}
      <section>
        <SectionHeader title="Your top genres" />
        <div className="flex flex-wrap gap-2">
          {["Synthwave", "Electronic", "Lo-Fi", "Rock", "Pop", "Indie Folk", "World", "Alternative"].map((g, i) => (
            <button
              key={g}
              onClick={() => { useWavely.getState().setLibraryTab("genres"); setView("library"); }}
              className={cn(
                "rounded-full px-4 py-2 text-sm font-medium transition hover:scale-[1.03]",
                i % 3 === 0 && "bg-primary/90 text-primary-foreground",
                i % 3 === 1 && "bg-accent text-accent-foreground",
                i % 3 === 2 && "bg-wav-elevated text-foreground border border-border",
              )}
            >
              {g}
            </button>
          ))}
        </div>
      </section>

      <footer className="flex items-center justify-center gap-2 pb-2 pt-4 text-xs text-muted-foreground">
        <ListMusic className="h-3.5 w-3.5" />
        Wavely prototype • Musicolet UX × Spotify design • v1.0.3-preview
      </footer>
    </div>
  );
}
