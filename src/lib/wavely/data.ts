import type { Album, Artist, LyricLine, Playlist, QueueDef, Track } from "./types";

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

export function fmtTime(sec: number): string {
  if (!isFinite(sec) || sec < 0) sec = 0;
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export function fmtLongTime(sec: number): string {
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  if (h > 0) return `${h} hr ${m} min`;
  return `${m} min`;
}

/** Spread lyric lines evenly across the track duration. */
function mkLyrics(lines: string[], duration: number): LyricLine[] {
  const step = duration / (lines.length + 2);
  return lines.map((text, i) => ({ time: +(step * (i + 1)).toFixed(1), text }));
}

/* ------------------------------------------------------------------ */
/* Albums / Artists                                                    */
/* ------------------------------------------------------------------ */

export const ALBUMS: Album[] = [
  { id: "al1", title: "Neon Horizon", artist: "Vector Dreams", artistId: "ar1", year: 2024, cover: "/covers/neon-horizon.png", genre: "Synthwave" },
  { id: "al2", title: "Midnight Bloom", artist: "Ivy & Ember", artistId: "ar2", year: 2023, cover: "/covers/midnight-bloom.png", genre: "Alternative" },
  { id: "al3", title: "Green Circuit", artist: "Vector Dreams", artistId: "ar1", year: 2025, cover: "/covers/green-circuit.png", genre: "Electronic" },
  { id: "al4", title: "Paper Planes", artist: "The Lanterns", artistId: "ar3", year: 2022, cover: "/covers/paper-planes.png", genre: "Indie Folk" },
  { id: "al5", title: "Deep Focus", artist: "Lo-Fi Collective", artistId: "ar4", year: 2024, cover: "/covers/deep-focus.png", genre: "Lo-Fi" },
  { id: "al6", title: "Velvet Static", artist: "Neon Riot", artistId: "ar5", year: 2023, cover: "/covers/velvet-static.png", genre: "Rock" },
  { id: "al7", title: "Golden Hour", artist: "Sola", artistId: "ar6", year: 2025, cover: "/covers/golden-hour.png", genre: "Pop" },
  { id: "al8", title: "Echoes of Tehran", artist: "Ava Rostami", artistId: "ar7", year: 2024, cover: "/covers/persian-echoes.png", genre: "World" },
  // ---- online-only catalogue (streaming, not on device) ----
  // releasedAt powers the Explore windows: 1 week / 2 weeks / 1 month / since last visit
  { id: "al9", title: "Chrome City", artist: "Midnight Arcade", artistId: "ar8", year: 2025, cover: "/covers/online-chrome-city.png", genre: "Synthpop", origin: "online", releasedAt: Date.now() - 3 * 86400000 },
  { id: "al10", title: "Violet Summer", artist: "Luna Waves", artistId: "ar9", year: 2024, cover: "/covers/online-violet-summer.png", genre: "Dream Pop", origin: "online", releasedAt: Date.now() - 12 * 86400000 },
  { id: "al11", title: "Golden Retro", artist: "Aria Vance", artistId: "ar10", year: 2025, cover: "/covers/online-golden-retro.png", genre: "Pop", origin: "online", releasedAt: Date.now() - 26 * 86400000 },
];

export const ARTISTS: Artist[] = [
  { id: "ar1", name: "Vector Dreams", image: "/covers/neon-horizon.png", albumIds: ["al1", "al3"] },
  { id: "ar2", name: "Ivy & Ember", image: "/covers/midnight-bloom.png", albumIds: ["al2"] },
  { id: "ar3", name: "The Lanterns", image: "/covers/paper-planes.png", albumIds: ["al4"] },
  { id: "ar4", name: "Lo-Fi Collective", image: "/covers/deep-focus.png", albumIds: ["al5"] },
  { id: "ar5", name: "Neon Riot", image: "/covers/velvet-static.png", albumIds: ["al6"] },
  { id: "ar6", name: "Sola", image: "/covers/golden-hour.png", albumIds: ["al7"] },
  { id: "ar7", name: "Ava Rostami", image: "/covers/persian-echoes.png", albumIds: ["al8"] },
  { id: "ar8", name: "Midnight Arcade", image: "/covers/online-chrome-city.png", albumIds: ["al9"] },
  { id: "ar9", name: "Luna Waves", image: "/covers/online-violet-summer.png", albumIds: ["al10"] },
  { id: "ar10", name: "Aria Vance", image: "/covers/online-golden-retro.png", albumIds: ["al11"] },
];

/* ------------------------------------------------------------------ */
/* Tracks                                                              */
/* ------------------------------------------------------------------ */

const F_MAIN = "/storage/emulated/0/Music";
const F_DL = "/storage/emulated/0/Music/Downloads";
const F_FLAC = "/storage/emulated/0/Music/FLAC";
const F_ONLINE = "online"; // virtual — streamed, no file on disk
/** Wavely download root — user-configurable in Settings (prototype value). */
export const DOWNLOAD_ROOT = "/storage/emulated/0/Music/Wavely";
/** Resolves the organised path for a downloaded track: {Country}/{Genre} template. */
export function downloadedFolder(country: string, genre: string): string {
  return `${DOWNLOAD_ROOT}/${country}/${genre}`;
}

interface Seed {
  id: string;
  title: string;
  albumId: string;
  n: number;
  d: number;
  lyrics?: string[];
}

const SEEDS: Seed[] = [
  // al1 — Neon Horizon
  { id: "t01", title: "Neon Horizon", albumId: "al1", n: 1, d: 252, lyrics: [
    "City lights are calling out my name",
    "Every street is glowing like a flame",
    "I was lost inside the static noise",
    "Now the signal's crystal clear and bright",
    "Take me to the neon horizon",
    "Where the night and morning meet",
    "We were running out of time",
    "Now we're running out of sight",
    "Hearts beat in electric blue and green",
    "The brightest wave I've ever seen",
    "Take me to the neon horizon",
    "Let the silence turn to sound",
  ]},
  { id: "t02", title: "Midnight Drive", albumId: "al1", n: 2, d: 228 },
  { id: "t03", title: "Chrome Sunset", albumId: "al1", n: 3, d: 301 },
  { id: "t04", title: "Laser Rain", albumId: "al1", n: 4, d: 215 },
  // al2 — Midnight Bloom
  { id: "t05", title: "Midnight Bloom", albumId: "al2", n: 1, d: 245, lyrics: [
    "Something's growing in the dark of me",
    "Quiet as a whisper, hard as steel",
    "I buried all my softness in the ground",
    "Now it's coming back, I feel it now",
    "Like a midnight bloom",
    "Opening too soon",
    "Nobody ever taught me how",
    "To be gentle with the light",
    "Like a midnight bloom",
    "Reaching for the moon",
    "I'll be tender, I'll be wild",
    "I'll be everything tonight",
  ]},
  { id: "t06", title: "Thornless", albumId: "al2", n: 2, d: 202 },
  { id: "t07", title: "Petals in the Wind", albumId: "al2", n: 3, d: 284 },
  { id: "t08", title: "Greenhouse", albumId: "al2", n: 4, d: 236 },
  // al3 — Green Circuit
  { id: "t09", title: "Green Circuit", albumId: "al3", n: 1, d: 220, lyrics: [
    "Woke up wired to the frequency",
    "Pulses running underneath my skin",
    "Every heartbeat is a broken beat",
    "Every silence is about to begin",
    "I am the green circuit",
    "Current in my veins",
    "I am the green circuit",
    "Dancing through the waves",
    "Voltage in the morning light",
    "Everything is amplified",
    "I am the green circuit",
    "And I finally feel alive",
  ]},
  { id: "t10", title: "Overclock", albumId: "al3", n: 2, d: 258 },
  { id: "t11", title: "Pulse Width", albumId: "al3", n: 3, d: 192 },
  { id: "t12", title: "Silicon Dreams", albumId: "al3", n: 4, d: 324 },
  // al4 — Paper Planes
  { id: "t13", title: "Paper Planes", albumId: "al4", n: 1, d: 234, lyrics: [
    "We folded all our summer into wings",
    "Threw our little paper planes downtown",
    "Some of them came falling down in flames",
    "Some of them are still up in the clouds",
    "If you're waiting for a sign",
    "This is it, this is now",
    "Let the paper planes remind us",
    "How we swore we'd never bow",
    "Oh, the wind knows where we're going",
    "Even when we don't know how",
  ]},
  { id: "t14", title: "Maple & Pine", albumId: "al4", n: 2, d: 261 },
  { id: "t15", title: "Campfire Stories", albumId: "al4", n: 3, d: 218 },
  { id: "t16", title: "Northern Lights", albumId: "al4", n: 4, d: 292 },
  // al5 — Deep Focus
  { id: "t17", title: "Deep Focus", albumId: "al5", n: 1, d: 178 },
  { id: "t18", title: "Rainy Window", albumId: "al5", n: 2, d: 195 },
  { id: "t19", title: "Cassette Hearts", albumId: "al5", n: 3, d: 182 },
  { id: "t20", title: "Study Lamp", albumId: "al5", n: 4, d: 210 },
  { id: "t21", title: "Slow Coffee", albumId: "al5", n: 5, d: 246 },
  // al6 — Velvet Static
  { id: "t22", title: "Velvet Static", albumId: "al6", n: 1, d: 213, lyrics: [
    "Turn it up until the walls give in",
    "Velvet static on my radio",
    "We were born inside the feedback din",
    "Loud enough to let the whole town know",
    "Break, break the silence",
    "Nothing left to prove",
    "Break, break the silence",
    "Velvet static, we choose the noise",
  ]},
  { id: "t23", title: "Break the Silence", albumId: "al6", n: 2, d: 242 },
  { id: "t24", title: "Amplifier", albumId: "al6", n: 3, d: 198 },
  { id: "t25", title: "Feedback Loop", albumId: "al6", n: 4, d: 284 },
  // al7 — Golden Hour
  { id: "t26", title: "Golden Hour", albumId: "al7", n: 1, d: 206, lyrics: [
    "Sunlight dripping through the afternoon",
    "Painting every rooftop amber bright",
    "You said summer ends a bit too soon",
    "So we're staying for the golden hour tonight",
    "Stay, stay awhile",
    "Watch the day go soft and slow",
    "Stay, stay awhile",
    "Every ending glows, you know",
  ]},
  { id: "t27", title: "Sunbeam", albumId: "al7", n: 2, d: 188 },
  { id: "t28", title: "Tangerine Sky", albumId: "al7", n: 3, d: 224 },
  { id: "t29", title: "Butterflies", albumId: "al7", n: 4, d: 201 },
  { id: "t30", title: "Stay Awhile", albumId: "al7", n: 5, d: 250 },
  // al8 — Echoes of Tehran
  { id: "t31", title: "Echoes of Tehran", albumId: "al8", n: 1, d: 272, lyrics: [
    "Old city breathing under midnight lamps",
    "Tar strings floating over rooftop steps",
    "Grandmother's songs still live inside the walls",
    "Echoes bouncing down the alleyways",
    "Tehran, Tehran",
    "Your memories are made of sound",
    "Tehran, Tehran",
    "Every stone a beaten drum",
    "And I carry you wherever I go",
    "A melody I'll always know",
  ]},
  { id: "t32", title: "Bazaar Nights", albumId: "al8", n: 2, d: 227 },
  { id: "t33", title: "Damavand", albumId: "al8", n: 3, d: 312 },
  { id: "t34", title: "Saffron Sky", albumId: "al8", n: 4, d: 238 },
  // al9 — Chrome City (online: Midnight Arcade, US)
  { id: "t35", title: "Chrome City", albumId: "al9", n: 1, d: 231, lyrics: [
    "Headlights melting on the boulevard",
    "Every window is a movie screen",
    "We drive until the city turns to chrome",
    "Nothing here is quite what it seems",
    "Chrome city, take me higher",
    "Streetlights painting lines of fire",
    "Chrome city, don't look down",
    "We're electric tonight",
  ]},
  { id: "t36", title: "Night Circuit", albumId: "al9", n: 2, d: 205 },
  { id: "t37", title: "Static Love", albumId: "al9", n: 3, d: 247 },
  { id: "t38", title: "Drive Forever", albumId: "al9", n: 4, d: 274 },
  // al10 — Violet Summer (online: Luna Waves, UK)
  { id: "t39", title: "Violet Summer", albumId: "al10", n: 1, d: 256, lyrics: [
    "The tide came in with violet light",
    "We stayed until the stars burned through",
    "You said the summer felt like you",
    "Soft and endless, out of view",
    "Violet summer, hold me under",
    "Salt and static, waves of wonder",
    "Violet summer, don't let go",
    "The night is ours, take it slow",
  ]},
  { id: "t40", title: "Undertow", albumId: "al10", n: 2, d: 223 },
  { id: "t41", title: "Glass Coast", albumId: "al10", n: 3, d: 268 },
  { id: "t42", title: "Slow Tide", albumId: "al10", n: 4, d: 241 },
  // al11 — Golden Retro (online: Aria Vance, SE)
  { id: "t43", title: "Golden Retro", albumId: "al11", n: 1, d: 214 },
  { id: "t44", title: "Sugar Static", albumId: "al11", n: 2, d: 198 },
  { id: "t45", title: "Neon Heart", albumId: "al11", n: 3, d: 236, lyrics: [
    "You wear your heart in neon light",
    "A sign that flickers every night",
    "I read it from across the room",
    "Buzzing like a cheap perfume",
    "Neon heart, don't fade out on me",
    "Buzz if you still believe",
  ]},
  { id: "t46", title: "Afterglow", albumId: "al11", n: 4, d: 252 },
];

/** per-track metadata for online tracks (source, country, quality, downloads) */
const ONLINE_META: Record<
  string,
  { source: Track["source"]; country: string; quality: string; downloaded?: boolean }
> = {
  t35: { source: "spotify", country: "US", quality: "320" },
  t36: { source: "ytmusic", country: "US", quality: "320", downloaded: true },
  t37: { source: "spotify", country: "US", quality: "320" },
  t38: { source: "soundcloud", country: "US", quality: "256" },
  t39: { source: "jamendo", country: "UK", quality: "FLAC" },
  t40: { source: "jamendo", country: "UK", quality: "FLAC", downloaded: true },
  t41: { source: "jamendo", country: "UK", quality: "FLAC" },
  t42: { source: "soundcloud", country: "UK", quality: "256" },
  t43: { source: "spotify", country: "SE", quality: "320" },
  t44: { source: "ytmusic", country: "SE", quality: "320" },
  t45: { source: "spotify", country: "SE", quality: "320", downloaded: true },
  t46: { source: "ytmusic", country: "SE", quality: "256" },
};

export const TRACKS: Track[] = SEEDS.map((s, i) => {
  const album = ALBUMS.find((a) => a.id === s.albumId)!;
  const online = album.origin === "online";
  const meta = online ? ONLINE_META[s.id] : undefined;
  const isDownloaded = !!meta?.downloaded;
  return {
    id: s.id,
    title: s.title,
    artist: album.artist,
    artistId: album.artistId,
    album: album.title,
    albumId: album.id,
    genre: album.genre,
    folder: online
      ? isDownloaded
        ? downloadedFolder(meta!.country, album.genre) // organised save path
        : F_ONLINE
      : album.id === "al2" || album.id === "al6" || album.id === "al7"
        ? F_DL
        : album.id === "al4" || album.id === "al5"
          ? F_FLAC
          : F_MAIN,
    duration: s.d,
    year: album.year,
    trackNumber: s.n,
    addedAt: Date.now() - (SEEDS.length - i) * 86400000,
    // every 5th song was never touched → feeds the "Not played" smart row
    playCount: i % 5 === 0 ? 0 : online && !isDownloaded ? ((i * 3) % 4) + 1 : ((i * 7 + 3) % 14) + 1,
    lastPlayedAt: i % 5 === 0 ? undefined : online ? undefined : Date.now() - (i % 9) * 3600000,
    lyrics: s.lyrics ? mkLyrics(s.lyrics, s.d) : undefined,
    origin: online ? "online" : "local",
    source: meta?.source,
    downloaded: isDownloaded || undefined,
    country: meta?.country,
    quality: meta?.quality,
  };
});

export const trackById = new Map(TRACKS.map((t) => [t.id, t]));
export const albumById = new Map(ALBUMS.map((a) => [a.id, a]));
export const artistById = new Map(ARTISTS.map((a) => [a.id, a]));

export const albumCover = (albumId: string) => albumById.get(albumId)?.cover ?? "/covers/neon-horizon.png";

export function tracksOfAlbum(albumId: string): Track[] {
  return TRACKS.filter((t) => t.albumId === albumId).sort((a, b) => a.trackNumber - b.trackNumber);
}

export function tracksOfArtist(artistId: string): Track[] {
  return TRACKS.filter((t) => t.artistId === artistId);
}

export const GENRES = Array.from(new Set(ALBUMS.map((a) => a.genre))).sort();

/** On-device folders (scanned by Musicolet-style folder view). */
export const FOLDERS = [F_MAIN, F_DL, F_FLAC];

/* ------------------------------------------------------------------ */
/* Playlists & Queues                                                  */
/* ------------------------------------------------------------------ */

const pick = (...ids: string[]) => ids;

export const PLAYLISTS: Playlist[] = [
  { id: "pl1", name: "Morning Energy", description: "Start the day loud", trackIds: pick("t09", "t26", "t13", "t22", "t28"), createdAt: Date.now() - 40 * 86400000, origin: "local" },
  { id: "pl2", name: "Late Night Coding", description: "Deep flow, zero vocals", trackIds: pick("t17", "t18", "t19", "t20", "t21", "t12"), createdAt: Date.now() - 22 * 86400000, origin: "local" },
  { id: "pl3", name: "Persian Vibes", description: "Home, in melodies", trackIds: pick("t31", "t32", "t33", "t34"), createdAt: Date.now() - 10 * 86400000, origin: "local" },
  { id: "pl4", name: "Workout Beast", description: "Push one more rep", trackIds: pick("t22", "t23", "t24", "t10", "t25"), createdAt: Date.now() - 3 * 86400000, origin: "local" },
  // mixed → local files + online streams in one playlist (badges show which is which)
  { id: "pl5", name: "Global Top Hits", description: "Charts + your device picks, mixed", trackIds: pick("t03", "t35", "t26", "t43", "t24", "t38"), createdAt: Date.now() - 2 * 86400000, origin: "mixed" },
  { id: "pl6", name: "Indie Rising", description: "Fresh finds, updated weekly", trackIds: pick("t39", "t41", "t44", "t46", "t42"), createdAt: Date.now() - 1 * 86400000, origin: "online" },
  { id: "pl7", name: "Road Trip Mix", description: "Yours + the world's, shuffled", trackIds: pick("t02", "t36", "t28", "t45", "t31", "t37"), createdAt: Date.now() - 12 * 3600000, origin: "mixed" },
];

export const INITIAL_QUEUES: QueueDef[] = [
  { id: "q-main", name: "Main Queue", trackIds: TRACKS.map((t) => t.id), savedIndex: 0, savedPosition: 0, pinned: true },
  { id: "q-gym", name: "Gym Sessions", trackIds: pick("t22", "t24", "t10", "t23", "t25", "t02"), savedIndex: 0, savedPosition: 0 },
  { id: "q-drive", name: "Night Drive", trackIds: pick("t01", "t02", "t03", "t04", "t28"), savedIndex: 0, savedPosition: 0 },
  { id: "q-focus", name: "Deep Focus", trackIds: pick("t17", "t18", "t20", "t12", "t21"), savedIndex: 0, savedPosition: 0 },
  { id: "q-chill", name: "Sunday Chill", trackIds: pick("t26", "t27", "t29", "t30", "t13", "t14"), savedIndex: 0, savedPosition: 0 },
];

export const INITIAL_FAVORITES = ["t01", "t09", "t17", "t26", "t31", "t13", "t39"];

export const INITIAL_HISTORY = ["t26", "t17", "t35", "t01", "t31", "t09", "t13", "t22", "t28"];

/** Artists the user follows — Explore surfaces their new releases first. */
export const FOLLOWED_ARTIST_IDS = ["ar1", "ar8", "ar9"];

/** The app was last online 10 days ago — "since last visit" shows everything newer. */
export const LAST_ONLINE_AT = Date.now() - 10 * 86400000;

/** "3 d ago" / "2 w ago" style age label for release dates. */
export function fmtAge(releasedAt: number): string {
  const days = Math.max(0, Math.floor((Date.now() - releasedAt) / 86400000));
  if (days === 0) return "today";
  if (days === 1) return "yesterday";
  if (days < 7) return `${days}d ago`;
  if (days < 30) return `${Math.floor(days / 7)}w ago`;
  return `${Math.floor(days / 30)}mo ago`;
}
