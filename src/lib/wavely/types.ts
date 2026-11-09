export interface LyricLine {
  time: number; // seconds
  text: string;
}

export interface Track {
  id: string;
  title: string;
  artist: string;
  album: string;
  albumArtist?: string;
  genre: string;
  folder: string;
  duration: number; // seconds (approx until audio metadata loads)
  url: string;
  year?: number;
  addedAt: number;
  playCount: number;
  lastPlayedAt?: number;
  lyrics?: LyricLine[] | null;
  local?: boolean;
  source: "demo" | "local";
}

export interface Queue {
  id: string;
  name: string;
  trackIds: string[];
  position: number; // index of currently selected track
  savedPosition: number; // seconds, for resume when switching queues
}

export interface Playlist {
  id: string;
  name: string;
  trackIds: string[];
  createdAt: number;
}

export type RepeatMode = "off" | "all" | "one";

export type View = "library" | "search" | "ai" | "settings" | "equalizer";
