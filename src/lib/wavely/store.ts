"use client";

import { create } from "zustand";
import type { AppView, LibraryTab, QueueDef, RepeatMode, SongSortMode, Track } from "./types";
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

export const useWavely = create<WavelyState>((set, get) => ({
  view: "home",
  libraryTab: "songs",
  songSort: "title-asc",
  setView: (v) => set({ view: v }),
  setLibraryTab: (t) => set({ libraryTab: t }),
  setSongSort: (s) => set({ songSort: s }),

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
    // Persist the queue we're leaving (Musicolet position retention)
    const queues = s.queues.map((q) =>
      q.id === s.activeQueueId
        ? { ...q, savedIndex: s.index, savedPosition: s.position }
        : q,
    );
    // Reuse a queue with the same name, else take an empty/unused slot (max 20, Musicolet-style)
    let target = queues.find((q) => q.name === name && !q.pinned);
    if (!target) {
      const empty = queues.find((q) => q.trackIds.length === 0 && !q.pinned);
      if (empty) {
        target = { ...empty, name, trackIds, savedIndex: 0, savedPosition: 0 };
        queues[queues.indexOf(empty)] = target;
      } else if (queues.length < 20) {
        target = {
          id: `q-${now()}`,
          name,
          trackIds,
          savedIndex: 0,
          savedPosition: 0,
        };
        queues.push(target);
      } else {
        const slot = queues[queues.length - 1];
        target = { ...slot, name, trackIds, savedIndex: 0, savedPosition: 0 };
        queues[queues.indexOf(slot)] = target;
      }
    } else {
      target = { ...target, trackIds, savedIndex: startIndex, savedPosition: 0 };
      queues[queues.indexOf(target)] = target;
    }
    const firstId = trackIds[startIndex] ?? trackIds[0];
    const t = trackById.get(firstId);
    set({
      queues,
      activeQueueId: target.id,
      index: startIndex,
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
    let nextIndex: number;
    if (s.shuffle && q.trackIds.length > 1) {
      do {
        nextIndex = Math.floor(Math.random() * q.trackIds.length);
      } while (nextIndex === s.index);
    } else {
      nextIndex = s.index + 1;
      if (nextIndex >= q.trackIds.length) {
        if (s.repeat === "all" || !auto) nextIndex = 0;
        else {
          set({ position: q.trackIds.length ? 0 : 0, isPlaying: false });
          return;
        }
      }
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

export const allTracks = TRACKS;
