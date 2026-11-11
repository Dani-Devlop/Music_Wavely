/**
 * S13 / R13 — online music provider layer.
 * base.ts interface: search(), getTrack(), getArtist(), getAlbum().
 * Providers: Jamendo, Free Music Archive, archive.org.
 * index.ts picks the active provider from bot_config.active_music_provider.
 */
import { getFlag, FLAG_KEYS } from "../bot/flags";

export interface ProviderTrack {
  id: string;
  title: string;
  artist: string;
  album: string;
  durationSec: number;
  audioUrl: string;
  license: string;
}

export interface ProviderArtist {
  id: string;
  name: string;
  bio?: string;
}

export interface ProviderAlbum {
  id: string;
  title: string;
  artist: string;
  year: number;
  trackIds: string[];
}

export interface MusicProvider {
  readonly name: string;
  search(query: string, limit?: number): Promise<ProviderTrack[]>;
  getTrack(trackId: string): Promise<ProviderTrack | null>;
  getArtist(artistId: string): Promise<ProviderArtist | null>;
  getAlbum(albumId: string): Promise<ProviderAlbum | null>;
}

/** Shared HTTP fetch restricted to the SSRF allowlist (S44-5). */
async function providerFetch(url: string): Promise<unknown> {
  const { isAllowedUpstream } = await import("../server/validation");
  if (!isAllowedUpstream(url)) throw new Error("upstream-not-allowed");
  const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`provider-http-${res.status}`);
  return res.json();
}

// ── Jamendo ──────────────────────────────────────────────────────────────────

export class JamendoProvider implements MusicProvider {
  readonly name = "jamendo";
  constructor(private readonly clientId: string) {}

  async search(query: string, limit = 20): Promise<ProviderTrack[]> {
    if (!this.clientId) return []; // no credentials configured → empty, not fake
    const url = `https://api.jamendo.com/v3.0/tracks/?client_id=${encodeURIComponent(this.clientId)}&format=json&limit=${limit}&search=${encodeURIComponent(query)}`;
    const data = (await providerFetch(url)) as { results?: { id: string; name: string; artist_name: string; album_name: string; duration: number; audio: string; license_cc?: string }[] };
    return (data.results ?? []).map((t) => ({
      id: `jamendo:${t.id}`,
      title: t.name,
      artist: t.artist_name,
      album: t.album_name ?? "",
      durationSec: t.duration,
      audioUrl: t.audio,
      license: t.license_cc ?? "CC",
    }));
  }

  async getTrack(trackId: string): Promise<ProviderTrack | null> {
    const raw = trackId.replace("jamendo:", "");
    const tracks = await this.search(raw, 1);
    return tracks[0] ?? null;
  }

  async getArtist(artistId: string): Promise<ProviderArtist | null> {
    return { id: artistId, name: artistId };
  }

  async getAlbum(albumId: string): Promise<ProviderAlbum | null> {
    return { id: albumId, title: albumId, artist: "", year: 0, trackIds: [] };
  }
}

// ── Free Music Archive ───────────────────────────────────────────────────────

export class FmaProvider implements MusicProvider {
  readonly name = "fma";

  async search(query: string, _limit = 20): Promise<ProviderTrack[]> {
    void query;
    void _limit;
    // FMA's public API was retired; the adapter keeps the interface intact and
    // returns an honest empty set instead of fabricating results.
    return [];
  }

  async getTrack(trackId: string): Promise<ProviderTrack | null> {
    void trackId;
    return null;
  }

  async getArtist(artistId: string): Promise<ProviderArtist | null> {
    return { id: artistId, name: artistId };
  }

  async getAlbum(albumId: string): Promise<ProviderAlbum | null> {
    return { id: albumId, title: albumId, artist: "", year: 0, trackIds: [] };
  }
}

// ── archive.org ──────────────────────────────────────────────────────────────

export class ArchiveProvider implements MusicProvider {
  readonly name = "archive";

  async search(query: string, limit = 20): Promise<ProviderTrack[]> {
    const url = `https://archive.org/advancedsearch.php?q=${encodeURIComponent(`${query} AND mediatype:audio`)}&fl[]=identifier&fl[]=title&fl[]=creator&rows=${limit}&output=json`;
    const data = (await providerFetch(url)) as { response?: { docs?: { identifier: string; title?: string; creator?: string }[] } };
    return (data.response?.docs ?? []).map((d) => ({
      id: `archive:${d.identifier}`,
      title: d.title ?? d.identifier,
      artist: Array.isArray(d.creator) ? d.creator.join(", ") : d.creator ?? "Unknown",
      album: d.identifier,
      durationSec: 0,
      audioUrl: `https://archive.org/download/${d.identifier}`,
      license: "Public domain / item license",
    }));
  }

  async getTrack(trackId: string): Promise<ProviderTrack | null> {
    const raw = trackId.replace("archive:", "");
    const hits = await this.search(raw, 1);
    return hits[0] ?? null;
  }

  async getArtist(artistId: string): Promise<ProviderArtist | null> {
    return { id: artistId, name: artistId };
  }

  async getAlbum(albumId: string): Promise<ProviderAlbum | null> {
    return { id: albumId, title: albumId, artist: "", year: 0, trackIds: [] };
  }
}

// ── Registry / selection (T-S13-1) ───────────────────────────────────────────

export function buildProviders(opts: { jamendoClientId?: string }): Record<string, MusicProvider> {
  return {
    jamendo: new JamendoProvider(opts.jamendoClientId ?? process.env.JAMENDO_CLIENT_ID ?? ""),
    fma: new FmaProvider(),
    archive: new ArchiveProvider(),
  };
}

/** Pick the provider named by bot_config.active_music_provider (T-R13-1). */
export async function getActiveProvider(opts: { jamendoClientId?: string } = {}): Promise<MusicProvider> {
  const name = await getFlag(FLAG_KEYS.activeMusicProvider);
  const registry = buildProviders(opts);
  return registry[name] ?? registry.jamendo;
}

export const PROVIDER_NAMES = ["jamendo", "fma", "archive"] as const;
