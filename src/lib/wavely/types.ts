export interface LyricLine {
  time: number; // seconds
  text: string;
}

/** Streaming provider the track was found on. */
export type MusicSource = "spotify" | "ytmusic" | "jamendo" | "soundcloud";

export const SOURCE_LABELS: Record<MusicSource, string> = {
  spotify: "Spotify",
  ytmusic: "YT Music",
  jamendo: "Jamendo",
  soundcloud: "SoundCloud",
};

/**
 * Browsing mode — what the library shows.
 *  all    → everything, mixed, badges visible
 *  local  → on-device files + downloaded songs (offline-player feel)
 *  online → streaming catalogue (discovery feel)
 */
export type SourceMode = "all" | "local" | "online";

/** Where a track lives. "downloaded" tracks are online tracks saved to disk. */
export type TrackOrigin = "local" | "online";

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
  /** where the track comes from — "local" = file on device, "online" = streaming */
  origin: TrackOrigin;
  /** streaming provider (only for online tracks) */
  source?: MusicSource;
  /** online track saved to disk → behaves like a local file, playable offline */
  downloaded?: boolean;
  /** market/country tag — used by the {Country} folder-organisation token */
  country?: string;
  /** audio quality label shown in badges (e.g. "320", "FLAC") */
  quality?: string;
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
  /** "local" = on-device songs only, "online" = streaming only, "mixed" = both */
  origin: TrackOrigin | "mixed";
}

export interface Album {
  id: string;
  title: string;
  artist: string;
  artistId: string;
  year: number;
  cover: string;
  genre: string;
  /** online-only albums never live on the device */
  origin?: TrackOrigin;
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

export type SongFilter = "all" | "not-played";

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
