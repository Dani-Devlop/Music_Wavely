"use client";

import { create } from "zustand";
import type {
  AppView,
  LibraryTab,
  QueueDef,
  RepeatMode,
  SongSortMode,
  SourceMode,
  Track,
} from "./types";
import {
  INITIAL_FAVORITES,
  INITIAL_HISTORY,
  INITIAL_QUEUES,
  TRACKS,
  trackById,
} from "./data";

export const EQ_FREQS = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

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

  /* source modes — local vs online organisation */
  sourceMode: SourceMode; // browsing filter (all / local / online)
  isOffline: boolean; // simulated connection loss → forces local-only
  setSourceMode: (m: SourceMode) => void;
  setOffline: (v: boolean) => void;
  /** browsing mode after applying the offline constraint */
  effectiveMode: () => SourceMode;
  /** can this track actually play right now? */
  canPlayTrack: (t: Track | undefined) => boolean;
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
  setNowPlayingOpen: (v: boolean) => void;
  setQueueSheetOpen: (v: boolean) => void;
  setEqOpen: (v: boolean) => void;
  setSleepTimerOpen: (v: boolean) => void;

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
  addToQueue: (trackId: string) => void;
  removeFromQueue: (index: number) => void;
  moveInQueue: (from: number, to: number) => void;
  reorderQueue: (ids: string[]) => void;
  clearQueue: () => void;
}

const now = () => Date.now();

/** Offline simulation toggles force-browse the local side of the library. */
export const isTrackPlayable = (t: Track | undefined, isOffline: boolean): boolean => {
  if (!t) return false;
  if (t.origin === "local" || t.downloaded) return true; // files always work
  return !isOffline; // streamed tracks need a connection
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
      playbackNotice: v
        ? "You're offline — Wavely is now an offline player"
        : "Back online — streaming sources reconnected",
    }),
  effectiveMode: () => (get().isOffline ? "local" : get().sourceMode),
  canPlayTrack: (t) => isTrackPlayable(t, get().isOffline),
  toggleDownload: (trackId) => {
    const t = trackById.get(trackId);
    if (!t || t.origin !== "online") return;
    if (t.downloaded) {
      set({ playbackNotice: `Removed from device: ${t.title}` });
    } else {
      set({ playbackNotice: `Saved to ${get().downloadPath}/${t.country ?? "--"}/${t.genre}` });
    }
    // mutate the catalog entry so the badge flips everywhere
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
  setNowPlayingOpen: (v) => set({ nowPlayingOpen: v }),
  setQueueSheetOpen: (v) => set({ queueSheetOpen: v }),
  setEqOpen: (v) => set({ eqOpen: v }),
  setSleepTimerOpen: (v) => set({ sleepTimerOpen: v }),

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
    const available = trackIds.filter((id) => isTrackPlayable(trackById.get(id), s.isOffline));
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
          !isTrackPlayable(trackById.get(q.trackIds[idx]), s.isOffline)
        );
        return idx;
      }
      let idx = s.index;
      for (let step = 0; step < q.trackIds.length; step++) {
        idx = idx + 1 >= q.trackIds.length ? 0 : idx + 1;
        if (isTrackPlayable(trackById.get(q.trackIds[idx]), s.isOffline)) return idx;
        if (!auto) break; // manual skip just wraps once like before
      }
      return idx;
    };
    let nextIndex: number;
    const immediate = s.index + 1;
    if (immediate < q.trackIds.length && isTrackPlayable(trackById.get(q.trackIds[immediate]), s.isOffline)) {
      nextIndex = immediate;
    } else if (immediate >= q.trackIds.length && !auto) {
      nextIndex = 0;
    } else {
      nextIndex = pickNext();
    }
    if (auto && nextIndex === s.index && q.trackIds.length > 1 && !isTrackPlayable(trackById.get(q.trackIds[nextIndex]), s.isOffline)) {
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

  addToQueue: (trackId) =>
    set((s) => {
      const queues = s.queues.map((q) =>
        q.id === s.activeQueueId ? { ...q, trackIds: [...q.trackIds, trackId] } : q,
      );
      return { queues };
    }),

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
  useWavely((s) => isTrackPlayable(t, s.isOffline));

export { filterByMode };
export const allTracks = TRACKS;
