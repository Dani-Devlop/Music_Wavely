"use client";

import Image from "next/image";
import { useMemo, useRef, useState } from "react";
import { EqBars } from "../eq-bars";
import { SongRow } from "../song-row";
import { OfflineBanner } from "../source-mode-chips";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import {
  ALBUMS,
  ARTISTS,
  FOLDERS,
  GENRES,
  PLAYLISTS,
  TRACKS as TRACKS_ALL,
  fmtLongTime,
  fmtTime,
  trackById,
  tracksOfAlbum,
  tracksOfArtist,
} from "@/lib/wavely/data";
import { SONG_FILTER_LABELS, SONG_SORT_LABELS, type LibraryTab, type SongSortMode, type Track } from "@/lib/wavely/types";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import {
  ArrowDownUp,
  Check,
  ChevronLeft,
  ChevronRight,
  Disc3,
  Folder,
  History,
  Heart,
  ListMusic,
  ListPlus,
  MicVocal,
  MoreVertical,
  Music2,
  Play,
  Plus,
  RotateCcw,
  UserRound,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useToast } from "@/hooks/use-toast";

const DEFAULT_TABS: { id: LibraryTab; label: string; icon: React.ElementType }[] = [
  { id: "songs", label: "Songs", icon: Music2 },
  { id: "albums", label: "Albums", icon: Disc3 },
  { id: "artists", label: "Artists", icon: UserRound },
  { id: "genres", label: "Genres", icon: MicVocal },
  { id: "folders", label: "Folders", icon: Folder },
  { id: "playlists", label: "Playlists", icon: ListPlus },
  { id: "queues", label: "Queues", icon: ListMusic },
  { id: "favorites", label: "Favorites", icon: Heart },
  { id: "history", label: "History", icon: History },
];

const SORTS: SongSortMode[] = [
  "title-asc",
  "title-desc",
  "artist",
  "album",
  "year",
  "duration-asc",
  "duration-desc",
  "date-added",
  "play-count",
];

function sortTracks(tracks: Track[], mode: SongSortMode): Track[] {
  const arr = [...tracks];
  switch (mode) {
    case "title-asc": return arr.sort((a, b) => a.title.localeCompare(b.title));
    case "title-desc": return arr.sort((a, b) => b.title.localeCompare(a.title));
    case "artist": return arr.sort((a, b) => a.artist.localeCompare(b.artist) || a.title.localeCompare(b.title));
    case "album": return arr.sort((a, b) => a.album.localeCompare(b.album) || a.trackNumber - b.trackNumber);
    case "year": return arr.sort((a, b) => b.year - a.year || a.title.localeCompare(b.title));
    case "duration-asc": return arr.sort((a, b) => a.duration - b.duration);
    case "duration-desc": return arr.sort((a, b) => b.duration - a.duration);
    case "date-added": return arr.sort((a, b) => b.addedAt - a.addedAt);
    case "play-count": return arr.sort((a, b) => b.playCount - a.playCount);
  }
}

function TrackList({
  tracks,
  contextName,
}: {
  tracks: Track[];
  contextName: string;
}) {
  const playContext = useWavely((s) => s.playContext);
  const ids = tracks.map((t) => t.id);
  return (
    <div className="space-y-0.5">
      {tracks.map((t, i) => (
        <SongRow
          key={t.id}
          track={t}
          index={i}
          showIndex
          onPlay={() => playContext(contextName, ids, i)}
        />
      ))}
    </div>
  );
}

function AlbumGrid() {
  const playContext = useWavely((s) => s.playContext);
  const current = useCurrentTrack();
  // device albums only — online albums appear once at least one song is saved
  const albums = useMemo(
    () =>
      ALBUMS.filter(
        (a) => a.origin !== "online" || tracksOfAlbum(a.id).some((t) => t.downloaded),
      ),
    [],
  );
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
      {albums.map((a) => (
        <button
          key={a.id}
          onClick={() => playContext(a.title, tracksOfAlbum(a.id).map((t) => t.id), 0)}
          className="group rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent"
        >
          <div className="relative mb-3 aspect-square overflow-hidden rounded-lg bg-secondary">
            <Image src={a.cover} alt={a.title} fill sizes="(max-width: 640px) 45vw, 220px" className="object-cover" />
            {current?.albumId === a.id && (
              <span className="absolute left-2 top-2 rounded-full bg-black/60 px-2 py-1">
                <EqBars />
              </span>
            )}
            <span className="absolute bottom-2 right-2 flex h-11 w-11 translate-y-2 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-xl transition-all group-hover:translate-y-0 group-hover:opacity-100">
              <Play className="h-5 w-5 fill-primary-foreground" />
            </span>
          </div>
          <p className="truncate text-sm font-semibold">{a.title}</p>
          <p className="truncate text-xs text-muted-foreground">{a.year} • {a.artist}</p>
        </button>
      ))}
    </div>
  );
}

function ArtistList() {
  const playContext = useWavely((s) => s.playContext);
  const artists = useMemo(
    () =>
      ARTISTS.filter((a) => {
        const albums = a.albumIds.map((id) => ALBUMS.find((x) => x.id === id)!);
        return albums.some(
          (al) => al.origin !== "online" || tracksOfAlbum(al.id).some((t) => t.downloaded),
        );
      }),
    [],
  );
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
      {artists.map((a) => (
        <button
          key={a.id}
          onClick={() => playContext(a.name, tracksOfArtist(a.id).map((t) => t.id), 0)}
          className="group rounded-xl bg-wav-surface p-4 text-center transition hover:bg-accent"
        >
          <div className="relative mx-auto mb-3 h-24 w-24 overflow-hidden rounded-full bg-secondary">
            <Image src={a.image} alt={a.name} fill sizes="96px" className="object-cover" />
          </div>
          <p className="truncate text-sm font-semibold">{a.name}</p>
          <p className="text-xs text-muted-foreground">
            {a.albumIds.length} album{a.albumIds.length > 1 ? "s" : ""}
          </p>
        </button>
      ))}
    </div>
  );
}

function GenreList() {
  const playContext = useWavely((s) => s.playContext);
  const isDeviceTrack = (t: Track) => t.origin === "local" || !!t.downloaded;
  const genres = useMemo(() => {
    const device = new Set(TRACKS_ALL.filter(isDeviceTrack).map((t) => t.genre));
    return GENRES.filter((g) => device.has(g));
  }, []);
  return (
    <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
      {genres.map((g) => {
        const tracks = sortTracks(
          ALBUMS.filter((a) => a.genre === g)
            .flatMap((a) => tracksOfAlbum(a.id))
            .filter(isDeviceTrack),
          "title-asc",
        );
        return (
          <button
            key={g}
            onClick={() => playContext(g, tracks.map((t) => t.id), 0)}
            className="flex items-center gap-4 rounded-xl bg-wav-surface p-4 text-left transition hover:bg-accent"
          >
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-primary/15 text-primary">
              <MicVocal className="h-6 w-6" />
            </div>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold">{g}</p>
              <p className="text-xs text-muted-foreground">{tracks.length} songs</p>
            </div>
            <Play className="ml-auto h-4 w-4 text-muted-foreground" />
          </button>
        );
      })}
    </div>
  );
}

/** Musicolet-style long-press → opens the folder actions sheet. */
function useLongPress(onLongPress: () => void, ms = 450) {
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const start = () => {
    timer.current = setTimeout(() => {
      timer.current = null;
      onLongPress();
    }, ms);
  };
  const cancel = () => {
    if (timer.current) {
      clearTimeout(timer.current);
      timer.current = null;
    }
  };
  return {
    onPointerDown: start,
    onPointerUp: cancel,
    onPointerLeave: cancel,
    onPointerCancel: cancel,
    onContextMenu: (e: React.MouseEvent) => {
      e.preventDefault();
      onLongPress();
    },
  };
}

function FolderList() {
  const playContext = useWavely((s) => s.playContext);
  const openFolderActions = useWavely((s) => s.openFolderActions);
  // on-device scan targets + every organised Wavely download folder in use
  const folders = useMemo(() => {
    const dlFolders = Array.from(
      new Set(TRACKS_ALL.filter((t) => t.downloaded).map((t) => t.folder)),
    );
    return [...FOLDERS, ...dlFolders.filter((f) => !FOLDERS.includes(f))];
  }, []);
  return (
    <div className="space-y-2">
      <p className="px-1 text-xs text-muted-foreground">
        Tap to play • long-press or ⋯ for folder options — playing a folder names the queue after
        it, Musicolet style.
      </p>
      {folders.map((f) => (
        <FolderRow key={f} folder={f} subfolders={folders.filter((x) => x !== f && x.startsWith(f + "/")).length} />
      ))}
    </div>
  );
}

function FolderRow({ folder: f, subfolders }: { folder: string; subfolders: number }) {
  const playContext = useWavely((s) => s.playContext);
  const openFolderActions = useWavely((s) => s.openFolderActions);
  const tracks = TRACKS_IN_FOLDER(f);
  const short = f.split("/").filter(Boolean).slice(-1)[0];
  const isWavely = f.includes("/Music/Wavely");
  const total = tracks.reduce((a, t) => a + t.duration, 0);
  const longPress = useLongPress(() => openFolderActions(f));
  return (
    <div
      {...longPress}
      onClick={() => playContext(short, tracks.map((t) => t.id), 0)}
      className="group flex w-full cursor-pointer items-center gap-4 rounded-xl bg-wav-surface p-4 text-left transition hover:bg-accent"
    >
      <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-primary/15 text-primary">
        <Folder className="h-6 w-6" />
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-semibold">
          /{short}
          {isWavely && (
            <span className="ml-2 rounded bg-primary/15 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wide text-primary">
              Wavely downloads
            </span>
          )}
        </p>
        <p className="truncate text-xs text-muted-foreground">
          {f}
          {subfolders > 0 && ` • ${subfolders} subfolder${subfolders > 1 ? "s" : ""}`}
        </p>
        <p className="truncate text-[11px] text-muted-foreground/80">
          {tracks.length} songs • {fmtLongTime(total)}
        </p>
      </div>
      <button
        onClick={(e) => {
          e.stopPropagation();
          openFolderActions(f);
        }}
        aria-label={`Folder options for ${short}`}
        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
      >
        <MoreVertical className="h-4 w-4" />
      </button>
    </div>
  );
}

function TRACKS_IN_FOLDER(folder: string): Track[] {
  // Musicolet semantics: the folder AND its subfolders
  return TRACKS_ALL.filter((t) => t.folder === folder || t.folder.startsWith(folder + "/"));
}

function PlaylistList() {
  const playContext = useWavely((s) => s.playContext);
  const { toast } = useToast();
  const [newName, setNewName] = useState("");
  const [creating, setCreating] = useState(false);
  const playlists = useMemo(
    () => PLAYLISTS.filter((p) => p.origin === "local" || p.origin === "mixed"),
    [],
  );
  const covers = ["/covers/green-circuit.png", "/covers/deep-focus.png", "/covers/persian-echoes.png", "/covers/velvet-static.png", "/covers/golden-hour.png", "/covers/paper-planes.png"];

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
      {playlists.map((p, i) => (
        <button
          key={p.id}
          onClick={() => playContext(p.name, p.trackIds, 0)}
          className="group rounded-xl bg-wav-surface p-3 text-left transition hover:bg-accent"
        >
          <div className="relative mb-3 aspect-square overflow-hidden rounded-lg bg-secondary">
            <Image src={covers[i % covers.length]} alt={p.name} fill sizes="(max-width: 640px) 45vw, 220px" className="object-cover" />
            <span className="absolute bottom-2 right-2 flex h-11 w-11 translate-y-2 items-center justify-center rounded-full bg-primary text-primary-foreground opacity-0 shadow-xl transition-all group-hover:translate-y-0 group-hover:opacity-100">
              <Play className="h-5 w-5 fill-primary-foreground" />
            </span>
          </div>
          <p className="truncate text-sm font-semibold">{p.name}</p>
          <p className="truncate text-xs text-muted-foreground">{p.trackIds.length} songs</p>
        </button>
      ))}
      {/* Create playlist */}
      <div className="rounded-xl border border-dashed border-border bg-wav-surface/60 p-3">
        {creating ? (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (newName.trim()) {
                toast({ description: `Playlist "${newName.trim()}" created` });
                setNewName("");
                setCreating(false);
              }
            }}
            className="flex h-full flex-col justify-center gap-2"
          >
            <Input
              autoFocus
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              placeholder="Playlist name"
              className="h-9 text-sm"
            />
            <div className="flex gap-2">
              <Button type="submit" size="sm" className="h-8 flex-1 text-xs">Create</Button>
              <Button type="button" size="sm" variant="ghost" className="h-8 flex-1 text-xs" onClick={() => setCreating(false)}>
                Cancel
              </Button>
            </div>
          </form>
        ) : (
          <button
            onClick={() => setCreating(true)}
            className="flex h-full w-full flex-col items-center justify-center gap-2 text-muted-foreground transition hover:text-foreground"
          >
            <span className="flex h-10 w-10 items-center justify-center rounded-full bg-accent">
              <Plus className="h-5 w-5" />
            </span>
            <span className="text-xs font-medium">Create playlist</span>
          </button>
        )}
      </div>
    </div>
  );
}

function QueueList() {
  const queues = useWavely((s) => s.queues);
  const activeQueueId = useWavely((s) => s.activeQueueId);
  const selectQueue = useWavely((s) => s.selectQueue);
  const setQueueSheetOpen = useWavely((s) => s.setQueueSheetOpen);
  const { toast } = useToast();
  const [newName, setNewName] = useState("");
  const createQueue = useWavely((s) => s.createQueue);

  return (
    <div className="space-y-2">
      <p className="px-1 pb-1 text-xs text-muted-foreground">
        Musicolet-style multi-queue: every queue keeps its position. Tap a queue to switch, long-press style menu in the sheet.
      </p>
      {queues.map((q) => {
        const tracks = q.trackIds.map((id) => trackById.get(id)).filter(Boolean) as Track[];
        const total = tracks.reduce((acc, t) => acc + t.duration, 0);
        const isActive = q.id === activeQueueId;
        return (
          <div
            key={q.id}
            className={cn(
              "flex items-center gap-4 rounded-xl p-4 transition",
              isActive ? "bg-primary/10 ring-1 ring-primary/40" : "bg-wav-surface hover:bg-accent",
            )}
          >
            <button
              onClick={() => {
                selectQueue(q.id);
                setQueueSheetOpen(true);
              }}
              className="flex min-w-0 flex-1 items-center gap-4 text-left"
            >
              <div className={cn(
                "flex h-12 w-12 shrink-0 items-center justify-center rounded-xl",
                isActive ? "bg-primary text-primary-foreground" : "bg-primary/15 text-primary",
              )}>
                <ListMusic className="h-6 w-6" />
              </div>
              <div className="min-w-0">
                <p className={cn("truncate text-sm font-semibold", isActive && "text-primary")}>
                  {q.name}
                  {q.pinned && <span className="ml-2 rounded bg-accent px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground">PINNED</span>}
                  {isActive && <span className="ml-2 rounded bg-primary px-1.5 py-0.5 text-[10px] font-bold text-primary-foreground">PLAYING</span>}
                </p>
                <p className="text-xs text-muted-foreground">
                  {q.trackIds.length} songs • {fmtLongTime(total)}
                  {!q.pinned && q.savedPosition > 0 && ` • resume ${fmtTime(q.savedPosition)}`}
                </p>
              </div>
            </button>
            {isActive && <EqBars className="mr-1" />}
          </div>
        );
      })}
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (newName.trim()) {
            createQueue(newName.trim());
            toast({ description: `Queue "${newName.trim()}" created (${queues.length + 1}/20)` });
            setNewName("");
          }
        }}
        className="flex gap-2 pt-1"
      >
        <Input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder={`New queue (${queues.length}/20 slots used)`} className="h-10" />
        <Button type="submit" size="icon" className="h-10 w-10 shrink-0" aria-label="Create queue">
          <Plus className="h-5 w-5" />
        </Button>
      </form>
    </div>
  );
}

export function LibraryView() {
  const libraryTab = useWavely((s) => s.libraryTab);
  const setLibraryTab = useWavely((s) => s.setLibraryTab);
  const songSort = useWavely((s) => s.songSort);
  const setSongSort = useWavely((s) => s.setSongSort);
  const songFilter = useWavely((s) => s.songFilter);
  const setSongFilter = useWavely((s) => s.setSongFilter);
  const favorites = useWavely((s) => s.favorites);
  const history = useWavely((s) => s.history);
  const playContext = useWavely((s) => s.playContext);
  const cachedIds = useWavely((s) => s.cachedIds);
  const libraryTabsOrder = useWavely((s) => s.libraryTabsOrder);
  const moveLibraryTab = useWavely((s) => s.moveLibraryTab);
  const resetLibraryTabs = useWavely((s) => s.resetLibraryTabs);
  const [query, setQuery] = useState("");
  const [editingTabs, setEditingTabs] = useState(false);
  const dragIndex = useRef<number | null>(null);

  const orderedTabs = useMemo(() => {
    const byId = new Map(DEFAULT_TABS.map((t) => [t.id, t]));
    const main = libraryTabsOrder.map((id) => byId.get(id)).filter(Boolean) as typeof DEFAULT_TABS;
    const missing = DEFAULT_TABS.filter((t) => !libraryTabsOrder.includes(t.id));
    return [...main, ...missing];
  }, [libraryTabsOrder]);

  // Library = the device (Musicolet world): local files + songs saved from online
  const isDeviceTrack = (t: Track) => t.origin === "local" || !!t.downloaded;

  const songs = useMemo(
    () =>
      sortTracks(
        [...TRACKS_ALL]
          .filter(isDeviceTrack)
          .filter((t) =>
            songFilter === "not-played" ? t.playCount === 0
            : songFilter === "saved" ? !!t.downloaded
            : songFilter === "cached" ? cachedIds.includes(t.id)
            : true,
          )
          .filter(
            (t) =>
              t.title.toLowerCase().includes(query.toLowerCase()) ||
              t.artist.toLowerCase().includes(query.toLowerCase()) ||
              t.album.toLowerCase().includes(query.toLowerCase()),
          ),
        songSort,
      ),
    [query, songSort, songFilter, cachedIds],
  );

  // Favorites span both worlds — liked online streams stay in the list,
  // marked with their ☁ Online badge (local songs show nothing).
  const favTracks = useMemo(
    () => favorites.map((id) => trackById.get(id)!).filter(Boolean),
    [favorites],
  );
  const histTracks = useMemo(
    () => history.map((id) => trackById.get(id)!).filter(Boolean).filter(isDeviceTrack),
    [history],
  );

  return (
    <div className="mx-auto max-w-6xl space-y-5 px-4 pb-8 pt-6 md:px-6">
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
        <div className="min-w-0 flex-1 basis-full sm:basis-auto">
          <h1 className="font-display text-2xl font-bold tracking-tight md:text-3xl">My Music</h1>
          <p className="truncate text-xs text-muted-foreground">
            On this device — your local player, Musicolet style
          </p>
        </div>
        <div className="flex w-full items-center gap-2 sm:w-auto">
          {libraryTab === "songs" && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="outline" size="sm" className="h-9 gap-2 rounded-full">
                  <ArrowDownUp className="h-3.5 w-3.5" />
                  <span className="hidden sm:inline">{SONG_SORT_LABELS[songSort]}</span>
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-52 rounded-xl">
                <DropdownMenuLabel className="text-primary">Sort by</DropdownMenuLabel>
                <DropdownMenuSeparator />
                {SORTS.map((s) => (
                  <DropdownMenuItem key={s} onClick={() => setSongSort(s)} className="flex items-center justify-between">
                    {SONG_SORT_LABELS[s]}
                    {songSort === s && <Check className="h-4 w-4 text-primary" />}
                  </DropdownMenuItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
          )}
          {(libraryTab === "songs" || libraryTab === "favorites" || libraryTab === "history") && (
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Filter…"
              className="h-9 w-28 rounded-full bg-secondary text-sm sm:w-40"
            />
          )}
          <Button
            size="sm"
            className="h-9 gap-2 rounded-full"
            onClick={() => {
              const ids = songs.map((t) => t.id);
              playContext("Shuffle all", ids, Math.floor(Math.random() * Math.max(1, ids.length)));
              useWavely.getState().toggleShuffle();
            }}
          >
            <Play className="h-4 w-4 fill-primary-foreground" /> Shuffle
          </Button>
        </div>
      </div>

      {/* source scope: the library itself is device-only (Musicolet world).
          Online browsing lives on Home + Search. */}
      <OfflineBanner />

      {libraryTab === "songs" && songFilter !== "all" && (
        <div className="flex items-center gap-2">
          <button
            onClick={() => setSongFilter("all")}
            className="inline-flex items-center gap-1.5 rounded-full bg-primary/15 px-3 py-1.5 text-xs font-semibold text-primary transition hover:bg-primary/25"
          >
            Filter: {SONG_FILTER_LABELS[songFilter]}
            <span aria-hidden="true">×</span>
            <span className="sr-only">Clear filter</span>
          </button>
        </div>
      )}

      {/* Tabs */}
      <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 md:mx-0 md:flex-wrap md:px-0">
        {orderedTabs.map((t, i) => {
          const Icon = t.icon;
          const active = libraryTab === t.id;
          if (editingTabs) {
            // edit mode: pill body is inert — it's a drag handle with arrow buttons
            return (
              <div
                key={t.id}
                draggable
                onDragStart={() => (dragIndex.current = i)}
                onDragOver={(e) => e.preventDefault()}
                onDrop={() => {
                  if (dragIndex.current !== null) moveLibraryTab(dragIndex.current, i);
                  dragIndex.current = null;
                }}
                className="flex shrink-0 cursor-grab items-center gap-1.5 rounded-full border border-dashed border-primary/50 bg-secondary px-4 py-2 text-sm font-medium transition-all"
              >
                <Icon className="h-4 w-4" />
                {t.label}
                <button
                  type="button"
                  onClick={() => moveLibraryTab(i, i - 1)}
                  disabled={i === 0}
                  aria-label={`Move ${t.label} earlier`}
                  className="flex h-6 w-6 items-center justify-center rounded-full transition-colors hover:bg-accent disabled:opacity-40"
                >
                  <ChevronLeft className="h-3.5 w-3.5" />
                </button>
                <button
                  type="button"
                  onClick={() => moveLibraryTab(i, i + 1)}
                  disabled={i === orderedTabs.length - 1}
                  aria-label={`Move ${t.label} later`}
                  className="flex h-6 w-6 items-center justify-center rounded-full transition-colors hover:bg-accent disabled:opacity-40"
                >
                  <ChevronRight className="h-3.5 w-3.5" />
                </button>
              </div>
            );
          }
          return (
            <button
              key={t.id}
              onClick={() => setLibraryTab(t.id)}
              className={cn(
                "flex shrink-0 items-center gap-1.5 rounded-full px-4 py-2 text-sm font-medium transition-all",
                active
                  ? "bg-primary text-primary-foreground shadow-md"
                  : "bg-secondary text-secondary-foreground hover:bg-accent",
              )}
              aria-pressed={active}
            >
              <Icon className="h-4 w-4" />
              {t.label}
            </button>
          );
        })}
        {editingTabs && (
          <button
            type="button"
            onClick={resetLibraryTabs}
            aria-label="Reset tab order"
            className="flex shrink-0 items-center gap-1.5 rounded-full bg-secondary px-4 py-2 text-sm font-medium text-secondary-foreground transition-all hover:bg-accent"
          >
            <RotateCcw className="h-4 w-4" />
            Reset
          </button>
        )}
        <button
          type="button"
          onClick={() => setEditingTabs((v) => !v)}
          aria-label="Customize tab order"
          aria-pressed={editingTabs}
          title="Customize tab order"
          className={cn(
            "flex h-9 shrink-0 items-center justify-center gap-1.5 rounded-full px-3 text-sm font-medium transition-all",
            editingTabs
              ? "bg-primary text-primary-foreground shadow-md"
              : "bg-secondary text-secondary-foreground hover:bg-accent",
          )}
        >
          <ArrowDownUp className="h-4 w-4" />
        </button>
      </div>

      <div className="min-h-[40vh]">
        {libraryTab === "songs" &&
          (songs.length ? (
            <TrackList tracks={songs} contextName="Songs" />
          ) : (
            <EmptyState icon={Music2} text="No songs match this filter" />
          ))}
        {libraryTab === "albums" && <AlbumGrid />}
        {libraryTab === "artists" && <ArtistList />}
        {libraryTab === "genres" && <GenreList />}
        {libraryTab === "folders" && <FolderList />}
        {libraryTab === "playlists" && <PlaylistList />}
        {libraryTab === "queues" && <QueueList />}
        {libraryTab === "favorites" &&
          (favTracks.length ? (
            <>
              <p className="px-1 pb-2 text-xs text-muted-foreground">
                Everything you love — device files and ☁ online streams side by side.
              </p>
              <TrackList tracks={favTracks} contextName="Favorites" />
            </>
          ) : (
            <EmptyState icon={Heart} text="Songs you love will live here" />
          ))}
        {libraryTab === "history" &&
          (histTracks.length ? (
            <TrackList tracks={histTracks} contextName="History" />
          ) : (
            <EmptyState icon={History} text="Your recently played tracks appear here" />
          ))}
      </div>
    </div>
  );
}

function EmptyState({ icon: Icon, text }: { icon: React.ElementType; text: string }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 rounded-2xl border border-dashed border-border py-16 text-muted-foreground">
      <Icon className="h-8 w-8" />
      <p className="text-sm">{text}</p>
    </div>
  );
}

/* lib helpers */
