"use client";

import { create } from "zustand";
import type {
  AppView,
  LibraryTab,
  QueueDef,
  RepeatMode,
  SongFilter,
  SongSortMode,
  SourceMode,
  Track,
} from "./types";
import {
  INITIAL_FAVORITES,
  INITIAL_HISTORY,
  INITIAL_QUEUES,
  LAST_ONLINE_AT,
  TRACKS,
  trackById,
} from "./data";

export const EQ_FREQS = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/**
 * Streaming cache: an online track being streamed fills its cache in
 * CACHE_FILL_SECONDS of playback (real app = progressive file cache).
 * Fully cached tracks keep playing with no connection, and can be
 * "saved" to the music folder instantly — no re-download needed.
 */
export const CACHE_FILL_SECONDS = 6;

/**
 * Hard ceiling of the streaming cache (user decision: max 400 MB).
 * The cache is invisible app storage — never a folder in the music library.
 * When it fills up, the oldest cached songs are evicted first (LRU).
 */
export const CACHE_LIMIT_MB = 400;

/** Rough per-track cache footprint by quality label (prototype estimate). */
export function cacheMbOf(t?: Track): number {
  if (!t) return 0;
  if (t.quality === "FLAC") return 28;
  if (t.quality === "256") return 7;
  return 9; // 320 kbps default
}

/** Total MB currently used by fully cached songs. */
export function cacheUsedMb(cachedIds: string[]): number {
  return cachedIds.reduce((sum, id) => sum + cacheMbOf(trackById.get(id)), 0);
}

export const EQ_PRESETS: Record<string, number[]> = {
  Flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  "Bass Boost": [7, 6, 4, 2, 0, 0, 0, 0, 0, 0],
  "Bass Reducer": [-6, -5, -3, -1, 0, 0, 0, 0, 0, 0],
  Rock: [5, 4, 2, -1, -2, 0, 2, 4, 5, 5],
  Pop: [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2],
  Jazz: [3, 2, 1, 2, -1, -1, 0, 1, 3, 4],
  Classical: [4, 3, 2, 0, -1, -1, 0, 2, 3, 4],
  Electronic: [5, 4, 1, 0, -2, 1, 1, 3, 5, 6],
  Vocal: [-3, -2, 0, 3, 5, 5, 3, 1, -1, -2],
};

interface WavelyState {
  /* navigation */
  view: AppView;
  libraryTab: LibraryTab;
  songSort: SongSortMode;
  setView: (v: AppView) => void;
  setLibraryTab: (t: LibraryTab) => void;
  setSongSort: (s: SongSortMode) => void;
  /** desktop sidebar: collapsed to an icon rail (Spotify-style toggle) */
  sidebarCollapsed: boolean;
  setSidebarCollapsed: (v: boolean) => void;
  libraryTabsOrder: LibraryTab[];
  setLibraryTabsOrder: (order: LibraryTab[]) => void;
  moveLibraryTab: (from: number, to: number) => void;
  resetLibraryTabs: () => void;

  /* source modes — local vs online organisation */
  sourceMode: SourceMode; // browsing filter (all / local / online)
  isOffline: boolean; // simulated connection loss → forces local-only
  setSourceMode: (m: SourceMode) => void;
  setOffline: (v: boolean) => void;
  /** browsing mode after applying the offline constraint */
  effectiveMode: () => SourceMode;
  /** can this track actually play right now? */
  canPlayTrack: (t: Track | undefined) => boolean;

  /* streaming cache — songs heard online stay playable offline */
  cacheProgress: Record<string, number>; // 0..1 while a track is being cached
  cachedIds: string[]; // fully cached → plays without internet, instant-save
  /** epoch ms of the last time the app was online — powers "since last visit" */
  lastOnlineAt: number;
  clearCache: () => void;
  /** Musicolet-style list filter for the Library songs tab */
  songFilter: SongFilter;
  setSongFilter: (f: SongFilter) => void;
  /** true → set the track's downloaded flag (save to organised folder) */
  toggleDownload: (trackId: string) => void;
  /** bumped on every download toggle so badge subscribers re-render */
  downloadVersion: number;
  /** transient notice surfaced as a toast by AppShell (store can't use hooks) */
  playbackNotice: string | null;
  clearPlaybackNotice: () => void;

  /* downloads & storage */
  downloadPath: string;
  folderTemplate: string; // e.g. "{Country}/{Genre}"
  audioFormat: "mp3-320" | "flac";
  setDownloadPath: (p: string) => void;
  setFolderTemplate: (t: string) => void;
  setAudioFormat: (f: "mp3-320" | "flac") => void;

  /* player core */
  queues: QueueDef[];
  activeQueueId: string;
  index: number; // index within active queue
  position: number; // seconds
  isPlaying: boolean;
  volume: number;
  shuffle: boolean;
  repeat: RepeatMode;
  speed: number;
  sleepEndsAt: number | null; // epoch ms; null = off
  favorites: string[];
  history: string[];

  /* overlays */
  nowPlayingOpen: boolean;
  queueSheetOpen: boolean;
  eqOpen: boolean;
  sleepTimerOpen: boolean;
  /** Spotify-style "⋯" track actions sheet — the track it is open for */
  actionsTrackId: string | null;
  /** Musicolet-style "long-press a folder" sheet — the folder path it is open for */
  folderActionsPath: string | null;
  setNowPlayingOpen: (v: boolean) => void;
  setQueueSheetOpen: (v: boolean) => void;
  setEqOpen: (v: boolean) => void;
  setSleepTimerOpen: (v: boolean) => void;
  openActions: (trackId: string) => void;
  closeActions: () => void;
  openFolderActions: (path: string) => void;
  closeFolderActions: () => void;

  /* equalizer */
  eqEnabled: boolean;
  eqPreset: string;
  eqBands: number[];
  preamp: number;
  setEqEnabled: (v: boolean) => void;
  setEqBand: (i: number, v: number) => void;
  setPreamp: (v: number) => void;
  applyEqPreset: (name: string) => void;

  /* actions */
  currentTrack: () => Track | undefined;
  activeQueue: () => QueueDef | undefined;
  playContext: (name: string, trackIds: string[], startIndex?: number) => void;
  selectQueue: (queueId: string) => void;
  createQueue: (name: string) => void;
  togglePlay: () => void;
  next: (auto?: boolean) => void;
  prev: () => void;
  seek: (sec: number) => void;
  tick: (dt: number) => void;
  toggleShuffle: () => void;
  cycleRepeat: () => void;
  setVolume: (v: number) => void;
  setSpeed: (v: number) => void;
  setSleepTimer: (minutes: number | "track" | null) => void;
  toggleFavorite: (trackId: string) => void;
  playNext: (trackId: string) => void;
  /** insert several tracks (in order) right after the current one */
  playNextMany: (trackIds: string[]) => void;
  addToQueue: (trackId: string) => void;
  /** append several tracks to the currently playing queue */
  addToQueueMany: (trackIds: string[]) => void;
  /** append several tracks to a specific queue (Musicolet "add to a queue") */
  addIdsToQueue: (queueId: string, trackIds: string[]) => void;
  removeFromQueue: (index: number) => void;
  moveInQueue: (from: number, to: number) => void;
  reorderQueue: (ids: string[]) => void;
  clearQueue: () => void;
}

const now = () => Date.now();

/** Offline simulation toggles force-browse the local side of the library. */
export const isTrackPlayable = (
  t: Track | undefined,
  isOffline: boolean,
  cachedIds: string[] = [],
): boolean => {
  if (!t) return false;
  if (t.origin === "local" || t.downloaded) return true; // files always work
  if (cachedIds.includes(t.id)) return true; // fully cached by streaming
  return !isOffline; // otherwise streamed tracks need a connection
};

/** Which tracks survive the current browsing mode (badge-aware filtering). */
const filterByMode = (tracks: Track[], mode: SourceMode): Track[] => {
  if (mode === "all") return tracks;
  if (mode === "local") return tracks.filter((t) => t.origin === "local" || t.downloaded);
  return tracks.filter((t) => t.origin === "online");
};

export const useWavely = create<WavelyState>((set, get) => ({
  view: "home",
  libraryTab: "songs",
  songSort: "title-asc",
  setView: (v) => set({ view: v }),
  setLibraryTab: (t) => set({ libraryTab: t }),
  setSongSort: (s) => set({ songSort: s }),
  libraryTabsOrder: ["songs", "albums", "artists", "genres", "folders", "playlists", "queues", "favorites", "history"],
  setLibraryTabsOrder: (order) => set({ libraryTabsOrder: order }),
  moveLibraryTab: (from, to) =>
    set((s) => {
      if (to < 0 || to >= s.libraryTabsOrder.length || from === to) return {};
      const order = [...s.libraryTabsOrder];
      const [moved] = order.splice(from, 1);
      order.splice(to, 0, moved);
      return { libraryTabsOrder: order };
    }),
  resetLibraryTabs: () =>
    set({ libraryTabsOrder: ["songs", "albums", "artists", "genres", "folders", "playlists", "queues", "favorites", "history"] }),

  sourceMode: "all",
  isOffline: false,
  setSourceMode: (m) => {
    if (m !== "local" && get().isOffline) {
      set({ playbackNotice: "You're offline — only on-device music is available" });
      return;
    }
    set({ sourceMode: m });
  },
  setOffline: (v) =>
    set({
      isOffline: v,
      ...(v ? { sourceMode: "local" as SourceMode } : {}),
      // coming back online resets the "since last visit" window
      ...(!v ? { lastOnlineAt: now() } : {}),
      playbackNotice: v
        ? "You're offline — Wavely is now an offline player"
        : "Back online — streaming sources reconnected",
    }),
  effectiveMode: () => (get().isOffline ? "local" : get().sourceMode),
  canPlayTrack: (t) => isTrackPlayable(t, get().isOffline, get().cachedIds),

  cacheProgress: {},
  cachedIds: [],
  lastOnlineAt: LAST_ONLINE_AT,
  clearCache: () =>
    set({ cacheProgress: {}, cachedIds: [], playbackNotice: "Streaming cache cleared" }),
  songFilter: "all",
  setSongFilter: (f) => set({ songFilter: f }),
  folderActionsPath: null,

  toggleDownload: (trackId) => {
    const t = trackById.get(trackId);
    if (!t || t.origin !== "online") return;
    if (t.downloaded) {
      set({ playbackNotice: `Removed from device: ${t.title}` });
    } else {
      // saving = real file in the music folder; it leaves the streaming cache
      const inCache = get().cachedIds.includes(trackId);
      set((s) => ({
        cachedIds: s.cachedIds.filter((id) => id !== trackId),
        cacheProgress: Object.fromEntries(
          Object.entries(s.cacheProgress).filter(([id]) => id !== trackId),
        ),
        playbackNotice: inCache
          ? `Saved from cache to ${get().downloadPath}/${t.country ?? "--"}/${t.genre} — cache space freed`
          : `Saved to ${get().downloadPath}/${t.country ?? "--"}/${t.genre}`,
      }));
    }
    // mutate the catalog entry so the row flips everywhere
    t.downloaded = t.downloaded ? undefined : true;
    t.folder = t.downloaded
      ? `${get().downloadPath}/${t.country ?? "--"}/${t.genre}`
      : "online";
    set((s) => ({ downloadVersion: s.downloadVersion + 1 }));
  },
  playbackNotice: null,
  clearPlaybackNotice: () => set({ playbackNotice: null }),
  downloadVersion: 0,

  downloadPath: "/storage/emulated/0/Music/Wavely",
  folderTemplate: "{Country}/{Genre}",
  audioFormat: "flac",
  setDownloadPath: (p) => set({ downloadPath: p }),
  setFolderTemplate: (t) => set({ folderTemplate: t }),
  setAudioFormat: (f) => set({ audioFormat: f }),

  queues: INITIAL_QUEUES.map((q) => ({ ...q, trackIds: [...q.trackIds] })),
  activeQueueId: "q-main",
  index: 0,
  position: 0,
  isPlaying: false,
  volume: 0.8,
  shuffle: false,
  repeat: "off",
  speed: 1,
  sleepEndsAt: null,
  favorites: [...INITIAL_FAVORITES],
  history: [...INITIAL_HISTORY],

  nowPlayingOpen: false,
  queueSheetOpen: false,
  eqOpen: false,
  sleepTimerOpen: false,
  sidebarCollapsed: false,
  setSidebarCollapsed: (v) => set({ sidebarCollapsed: v }),
  actionsTrackId: null,
  setNowPlayingOpen: (v) => set({ nowPlayingOpen: v }),
  setQueueSheetOpen: (v) => set({ queueSheetOpen: v }),
  setEqOpen: (v) => set({ eqOpen: v }),
  setSleepTimerOpen: (v) => set({ sleepTimerOpen: v }),
  openActions: (trackId) => set({ actionsTrackId: trackId }),
  closeActions: () => set({ actionsTrackId: null }),
  openFolderActions: (path) => set({ folderActionsPath: path }),
  closeFolderActions: () => set({ folderActionsPath: null }),

  eqEnabled: true,
  eqPreset: "Flat",
  eqBands: [...EQ_PRESETS.Flat],
  preamp: 0,
  setEqEnabled: (v) => set({ eqEnabled: v }),
  setEqBand: (i, v) =>
    set((s) => {
      const bands = [...s.eqBands];
      bands[i] = v;
      return { eqBands: bands, eqPreset: "Custom" };
    }),
  setPreamp: (v) => set({ preamp: v }),
  applyEqPreset: (name) =>
    set({ eqPreset: name, eqBands: [...(EQ_PRESETS[name] ?? EQ_PRESETS.Flat)] }),

  currentTrack: () => {
    const s = get();
    const q = s.queues.find((q) => q.id === s.activeQueueId);
    const id = q?.trackIds[s.index];
    return id ? trackById.get(id) : undefined;
  },
  activeQueue: () => get().queues.find((q) => q.id === get().activeQueueId),

  playContext: (name, trackIds, startIndex = 0) => {
    if (trackIds.length === 0) return;
    const s = get();
    // hard-block unavailable (offline) tracks from starting playback
    const available = trackIds.filter((id) =>
      isTrackPlayable(trackById.get(id), s.isOffline, s.cachedIds),
    );
    if (available.length === 0) {
      set({
        playbackNotice: s.isOffline
          ? `Can't play offline — download it or go back online`
          : `Can't play ${name}`,
      });
      return;
    }
    const ids = available;
    const startId = trackIds[startIndex];
    const safeIndex = startId && ids.includes(startId) ? ids.indexOf(startId) : 0;
    // Persist the queue we're leaving (Musicolet position retention)
    const queues = s.queues.map((q) =>
      q.id === s.activeQueueId
        ? { ...q, savedIndex: s.index, savedPosition: s.position }
        : q,
    );
    // reuse a queue with the same name, else take an empty/unused slot (max 20, Musicolet-style)
    let target = queues.find((q) => q.name === name && !q.pinned);
    if (!target) {
      const empty = queues.find((q) => q.trackIds.length === 0 && !q.pinned);
      if (empty) {
        target = { ...empty, name, trackIds: ids, savedIndex: 0, savedPosition: 0 };
        queues[queues.indexOf(empty)] = target;
      } else if (queues.length < 20) {
        target = {
          id: `q-${now()}`,
          name,
          trackIds: ids,
          savedIndex: 0,
          savedPosition: 0,
        };
        queues.push(target);
      } else {
        const slot = queues[queues.length - 1];
        target = { ...slot, name, trackIds: ids, savedIndex: 0, savedPosition: 0 };
        queues[queues.indexOf(slot)] = target;
      }
    } else {
      target = { ...target, trackIds: ids, savedIndex: safeIndex, savedPosition: 0 };
      queues[queues.indexOf(target)] = target;
    }
    const firstId = ids[safeIndex] ?? ids[0];
    const t = trackById.get(firstId);
    set({
      queues,
      activeQueueId: target.id,
      index: safeIndex,
      position: 0,
      isPlaying: true,
      history: t ? [t.id, ...s.history.filter((h) => h !== t.id)].slice(0, 24) : s.history,
    });
  },

  selectQueue: (queueId) => {
    const s = get();
    if (queueId === s.activeQueueId) return;
    const queues = s.queues.map((q) =>
      q.id === s.activeQueueId
        ? { ...q, savedIndex: s.index, savedPosition: s.position }
        : q,
    );
    const target = queues.find((q) => q.id === queueId);
    if (!target) return;
    const resumeIndex = Math.min(target.savedIndex, Math.max(0, target.trackIds.length - 1));
    set({
      queues,
      activeQueueId: queueId,
      index: resumeIndex,
      position: target.savedPosition,
      isPlaying: true,
    });
  },

  createQueue: (name) => {
    const s = get();
    if (s.queues.length >= 20) return;
    set({
      queues: [
        ...s.queues,
        { id: `q-${now()}`, name, trackIds: [], savedIndex: 0, savedPosition: 0 },
      ],
    });
  },

  togglePlay: () => set((s) => ({ isPlaying: !s.isPlaying })),

  next: (auto = false) => {
    const s = get();
    const q = s.queues.find((x) => x.id === s.activeQueueId);
    if (!q || q.trackIds.length === 0) return;
    if (auto && s.repeat === "one") {
      set({ position: 0 });
      return;
    }
    // skip unavailable (offline / not-downloaded) tracks when advancing
    const pickNext = (): number => {
      if (s.shuffle && q.trackIds.length > 1) {
        let idx = s.index;
        let guard = 0;
        do {
          idx = Math.floor(Math.random() * q.trackIds.length);
          guard++;
        } while (
          idx === s.index &&
          guard < 50 &&
          !isTrackPlayable(trackById.get(q.trackIds[idx]), s.isOffline, s.cachedIds)
        );
        return idx;
      }
      let idx = s.index;
      for (let step = 0; step < q.trackIds.length; step++) {
        idx = idx + 1 >= q.trackIds.length ? 0 : idx + 1;
        if (isTrackPlayable(trackById.get(q.trackIds[idx]), s.isOffline, s.cachedIds)) return idx;
        if (!auto) break; // manual skip just wraps once like before
      }
      return idx;
    };
    let nextIndex: number;
    const immediate = s.index + 1;
    if (
      immediate < q.trackIds.length &&
      isTrackPlayable(trackById.get(q.trackIds[immediate]), s.isOffline, s.cachedIds)
    ) {
      nextIndex = immediate;
    } else if (immediate >= q.trackIds.length && !auto) {
      nextIndex = 0;
    } else {
      nextIndex = pickNext();
    }
    if (
      auto &&
      nextIndex === s.index &&
      q.trackIds.length > 1 &&
      !isTrackPlayable(trackById.get(q.trackIds[nextIndex]), s.isOffline, s.cachedIds)
    ) {
      set({ isPlaying: false });
      return;
    }
    const t = trackById.get(q.trackIds[nextIndex]);
    set((st) => ({
      index: nextIndex,
      position: 0,
      history: t
        ? [t.id, ...st.history.filter((h) => h !== t.id)].slice(0, 24)
        : st.history,
    }));
  },

  prev: () => {
    const s = get();
    if (s.position > 3) {
      set({ position: 0 });
      return;
    }
    const q = s.queues.find((x) => x.id === s.activeQueueId);
    if (!q || q.trackIds.length === 0) return;
    const prevIndex = s.index - 1 < 0 ? q.trackIds.length - 1 : s.index - 1;
    set({ index: prevIndex, position: 0 });
  },

  seek: (sec) => set({ position: Math.max(0, sec) }),

  tick: (dt) => {
    const s = get();
    if (!s.isPlaying) return;
    const q = s.queues.find((x) => x.id === s.activeQueueId);
    const t = s.currentTrack();
    if (!q || !t) return;
    const newPos = s.position + dt * s.speed;
    if (newPos >= t.duration) {
      // sleep timer "end of track" handling happens in tick consumer
      get().next(true);
    } else {
      set({ position: newPos });
    }
    if (s.sleepEndsAt && now() >= s.sleepEndsAt) {
      set({ isPlaying: false, sleepEndsAt: null });
      return;
    }
    // streaming cache fills while listening online (offline = nothing to fetch)
    if (t.origin === "online" && !t.downloaded && !s.isOffline && !s.cachedIds.includes(t.id)) {
      const prev = s.cacheProgress[t.id] ?? 0;
      const progress = Math.min(1, prev + (dt * s.speed) / CACHE_FILL_SECONDS);
      if (progress >= 1) {
        set((st) => {
          // enforce the 400 MB ceiling — evict oldest fully-cached songs first (LRU)
          const ids = [...st.cachedIds, t.id];
          let used = cacheUsedMb(ids);
          const evicted: string[] = [];
          let i = 0;
          while (used > CACHE_LIMIT_MB && i < ids.length - 1) {
            evicted.push(ids[i]);
            used -= cacheMbOf(trackById.get(ids[i]));
            i++;
          }
          const kept = ids.slice(i);
          return {
            cachedIds: kept,
            cacheProgress: { ...st.cacheProgress, [t.id]: 1 },
            playbackNotice: evicted.length
              ? `Cache hit its ${CACHE_LIMIT_MB} MB limit — oldest cached songs freed`
              : `Cached — ${t.title} now plays offline`,
          };
        });
      } else {
        set((st) => ({ cacheProgress: { ...st.cacheProgress, [t.id]: progress } }));
      }
    }
  },

  toggleShuffle: () => set((s) => ({ shuffle: !s.shuffle })),
  cycleRepeat: () =>
    set((s) => ({
      repeat: s.repeat === "off" ? "all" : s.repeat === "all" ? "one" : "off",
    })),
  setVolume: (v) => set({ volume: Math.min(1, Math.max(0, v)) }),
  setSpeed: (v) => set({ speed: v }),

  setSleepTimer: (minutes) =>
    set({
      sleepEndsAt: minutes === null ? null : minutes === "track" ? -1 : now() + minutes * 60000,
    }),

  toggleFavorite: (trackId) =>
    set((s) => ({
      favorites: s.favorites.includes(trackId)
        ? s.favorites.filter((f) => f !== trackId)
        : [trackId, ...s.favorites],
    })),

  playNext: (trackId) =>
    set((s) => {
      const queues = s.queues.map((q) =>
        q.id === s.activeQueueId
          ? {
              ...q,
              trackIds: [
                ...q.trackIds.slice(0, s.index + 1),
                trackId,
                ...q.trackIds.slice(s.index + 1),
              ],
            }
          : q,
      );
      return { queues };
    }),

  playNextMany: (trackIds) =>
    set((s) => ({
      queues: s.queues.map((q) =>
        q.id === s.activeQueueId
          ? {
              ...q,
              trackIds: [
                ...q.trackIds.slice(0, s.index + 1),
                ...trackIds,
                ...q.trackIds.slice(s.index + 1),
              ],
            }
          : q,
      ),
    })),

  addToQueue: (trackId) =>
    set((s) => {
      const queues = s.queues.map((q) =>
        q.id === s.activeQueueId ? { ...q, trackIds: [...q.trackIds, trackId] } : q,
      );
      return { queues };
    }),

  addToQueueMany: (trackIds) =>
    set((s) => ({
      queues: s.queues.map((q) =>
        q.id === s.activeQueueId ? { ...q, trackIds: [...q.trackIds, ...trackIds] } : q,
      ),
    })),

  addIdsToQueue: (queueId, trackIds) =>
    set((s) => ({
      queues: s.queues.map((q) =>
        q.id === queueId ? { ...q, trackIds: [...q.trackIds, ...trackIds] } : q,
      ),
    })),

  removeFromQueue: (index) =>
    set((s) => {
      const queues = s.queues.map((q) => {
        if (q.id !== s.activeQueueId) return q;
        const ids = q.trackIds.filter((_, i) => i !== index);
        return { ...q, trackIds: ids, savedIndex: Math.min(q.savedIndex, Math.max(0, ids.length - 1)) };
      });
      const idx = index < s.index ? s.index - 1 : index === s.index ? s.index : s.index;
      return { queues, index: Math.min(idx, Math.max(0, (queues.find((q) => q.id === s.activeQueueId)?.trackIds.length ?? 1) - 1)) };
    }),

  moveInQueue: (from, to) =>
    set((s) => {
      const queues = s.queues.map((q) => {
        if (q.id !== s.activeQueueId) return q;
        const ids = [...q.trackIds];
        const [moved] = ids.splice(from, 1);
        ids.splice(to, 0, moved);
        return { ...q, trackIds: ids };
      });
      let index = s.index;
      if (from === s.index) index = to;
      else if (from < s.index && to >= s.index) index = s.index - 1;
      else if (from > s.index && to <= s.index) index = s.index + 1;
      return { queues, index };
    }),

  reorderQueue: (ids) =>
    set((s) => ({
      queues: s.queues.map((q) =>
        q.id === s.activeQueueId ? { ...q, trackIds: ids } : q,
      ),
      index: Math.max(0, ids.indexOf(s.queues.find((q) => q.id === s.activeQueueId)?.trackIds[s.index] ?? ids[0])),
    })),

  clearQueue: () =>
    set((s) => ({
      queues: s.queues.map((q) =>
        q.id === s.activeQueueId ? { ...q, trackIds: [], savedIndex: 0, savedPosition: 0 } : q,
      ),
      isPlaying: false,
      position: 0,
      index: 0,
    })),
}));

/** Convenience selector hooks */
export const useCurrentTrack = () => useWavely((s) => s.currentTrack());
export const useActiveQueue = () => useWavely((s) => s.activeQueue());
export const useEffectiveMode = () =>
  useWavely((s) => (s.isOffline ? "local" : s.sourceMode));
export const useIsTrackPlayable = (t: Track | undefined) =>
  useWavely((s) => isTrackPlayable(t, s.isOffline, s.cachedIds));
export const useCacheUsage = () =>
  useWavely((s) => cacheUsedMb(s.cachedIds));

export { filterByMode };
export const allTracks = TRACKS;
