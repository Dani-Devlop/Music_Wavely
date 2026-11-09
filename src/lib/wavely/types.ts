export interface LyricLine {
  time: number; // seconds
  text: string;
}

export interface Track {
  id: string;
  title: string;
  artist: string;
  artistId: string;
  album: string;
  albumId: string;
  genre: string;
  folder: string;
  duration: number; // seconds
  year: number;
  trackNumber: number;
  addedAt: number;
  playCount: number;
  lastPlayedAt?: number;
  lyrics?: LyricLine[];
}

export interface Album {
  id: string;
  title: string;
  artist: string;
  artistId: string;
  year: number;
  cover: string;
  genre: string;
}

export interface Artist {
  id: string;
  name: string;
  image: string; // derived from first album cover
  albumIds: string[];
}

export interface Playlist {
  id: string;
  name: string;
  description: string;
  trackIds: string[];
  createdAt: number;
}

/** Musicolet-style queue: 20 slots, position retention per queue. */
export interface QueueDef {
  id: string;
  name: string;
  trackIds: string[];
  /** index of the track that was playing when the user switched away */
  savedIndex: number;
  /** seconds into that track — for resume when switching queues */
  savedPosition: number;
  pinned?: boolean;
}

export type RepeatMode = "off" | "all" | "one";

export type LibraryTab =
  | "songs"
  | "albums"
  | "artists"
  | "genres"
  | "folders"
  | "playlists"
  | "queues"
  | "favorites"
  | "history";

export type AppView = "home" | "search" | "library" | "ai" | "settings";

export type SongSortMode =
  | "title-asc"
  | "title-desc"
  | "artist"
  | "album"
  | "year"
  | "duration-asc"
  | "duration-desc"
  | "date-added"
  | "play-count";

export const SONG_SORT_LABELS: Record<SongSortMode, string> = {
  "title-asc": "Title A → Z",
  "title-desc": "Title Z → A",
  artist: "Artist",
  album: "Album",
  year: "Year",
  "duration-asc": "Duration ↑",
  "duration-desc": "Duration ↓",
  "date-added": "Date added",
  "play-count": "Play count",
};
