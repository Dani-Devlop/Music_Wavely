/**
 * S07 / R07 — AI DJ: only is_mixed=true playlists are playable via /dj*;
 * personalization lives behind ai_dj_personalization_enabled and is NEVER
 * invoked without the flag (T-S07-2).
 */
import { db } from "@/lib/db";
import { getFlag, FLAG_KEYS } from "./flags";
import type { CommandContext, CommandReply } from "./commands";

export interface MixPlaylist {
  id: string;
  name: string;
  isMixed: boolean;
}

/** Endpoint-equivalent: getMixedPlaylists (T-S07-3 / T-R07-3). */
export async function getMixedPlaylists(userId: string): Promise<MixPlaylist[]> {
  const rows = await db.playlist.findMany({
    where: { userId, isMixed: true },
    select: { id: true, name: true, isMixed: true },
  });
  return rows;
}

/** /dj — list mix playlists. */
export async function djList(userId: string): Promise<CommandReply> {
  const mixes = await getMixedPlaylists(userId);
  if (mixes.length === 0) return { text: "No mix playlists yet — save a few mixes in the mini app first." };
  return {
    text: "Your mixes:",
    buttons: mixes.map((m) => ({ label: `▶ ${m.name}`, data: `dj_play:${m.id}` })),
  };
}

/** /dj_play <playlist_id> — play a mix (T-S07-1). */
export async function djPlay(userId: string, playlistId: string): Promise<CommandReply> {
  const pl = await db.playlist.findUnique({ where: { id: playlistId } });
  if (!pl || pl.userId !== userId) return { text: "Playlist not found." };
  if (!pl.isMixed) return { text: "Only mix playlists can be played by the AI DJ." };
  const tracks = await db.playlistTrack.findMany({ where: { playlistId }, orderBy: { position: "asc" } });
  if (tracks.length === 0) return { text: "This mix is empty." };
  return { text: `Playing mix "${pl.name}" — ${tracks.length} tracks queued.` };
}

export function djStop(): CommandReply {
  return { text: "AI DJ stopped." };
}

/**
 * Personalization entry — guarded by the flag. Returns null and does NOTHING
 * when ai_dj_personalization_enabled=false (T-S07-2 / T-R07-2 / T-S08-1).
 */
export async function personalizeIfEnabled(userId: string): Promise<string[] | null> {
  const enabled = (await getFlag(FLAG_KEYS.aiDjPersonalization)) === "true";
  if (!enabled) return null; // the personalized module is never even imported
  const { loadGatedModules } = await import("./flags");
  const modules = await loadGatedModules();
  if (!modules.aiDjPersonalization) return null;
  return modules.aiDjPersonalization.personalize(userId);
}

export async function handleDjCommand(ctx: CommandContext, raw: string): Promise<CommandReply> {
  const [cmd, arg] = raw.split(/\s+/);
  if (cmd === "/dj") return djList(ctx.from.id);
  if (cmd === "/dj_play") {
    if (!arg) return { text: "Usage: /dj_play <playlist_id>" };
    return djPlay(ctx.from.id, arg);
  }
  if (cmd === "/dj_stop") return djStop();
  return { text: "Unknown DJ command" };
}
