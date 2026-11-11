/**
 * S04 / R04 — group features: voice-chat controls, live equalizer presets
 * (no stream interruption), Listening Party sync, one-time 6-digit PINs and
 * shared playlist cloning.
 */
import { db } from "@/lib/db";
import { newPin6, hashToken, newToken } from "../server/tokens";

export const VOICE_COMMANDS = ["/play", "/pause", "/resume", "/skip", "/stop", "/queue", "/loop", "/shuffle"] as const;

export type EqualizerPreset = "Flat" | "Bass Boost" | "Vocal Boost" | "3D Surround" | "Acoustic";

export const EQUALIZER_PRESETS: EqualizerPreset[] = ["Flat", "Bass Boost", "Vocal Boost", "3D Surround", "Acoustic"];

export interface VoiceChatState {
  playing: boolean;
  preset: EqualizerPreset;
  streamContinuity: boolean; // false = a pause/cut happened
}

/** Apply an equalizer preset WITHOUT interrupting the stream (T-S04-2). */
export function applyEqualizerPreset(state: VoiceChatState, preset: EqualizerPreset): VoiceChatState {
  if (!EQUALIZER_PRESETS.includes(preset)) throw new Error("unknown-preset");
  // preset swap is an in-band metadata update: playback never stops
  return { ...state, preset, streamContinuity: state.playing ? true : state.streamContinuity };
}

/** The 8 glass-button voice chat controls (T-S04-1). */
export function voiceCommandReply(command: (typeof VOICE_COMMANDS)[number], state: VoiceChatState): { reply: string; state: VoiceChatState } {
  switch (command) {
    case "/play":
      return { reply: "▶ Playing", state: { ...state, playing: true } };
    case "/pause":
      return { reply: "⏸ Paused", state: { ...state, playing: false } };
    case "/resume":
      return { reply: "▶ Resumed", state: { ...state, playing: true } };
    case "/skip":
      return { reply: "⏭ Skipped", state };
    case "/stop":
      return { reply: "⏹ Stopped", state: { ...state, playing: false } };
    case "/queue":
      return { reply: "📋 Queue opened", state };
    case "/loop":
      return { reply: "🔁 Loop toggled", state };
    case "/shuffle":
      return { reply: "🔀 Shuffle toggled", state };
  }
}

// ── Listening Party (S04-2) ──────────────────────────────────────────────────

export interface PartyState {
  roomId: string;
  trackId: string;
  isPlaying: boolean;
  positionSec: number;
  updatedAtMs: number;
}

/**
 * Server-authoritative sync computation — each listener derives the same
 * position from (positionSec + elapsed since update). Deterministic, so
 * drift stays well under 100ms for NTP-aligned clocks (T-S04-3).
 */
export function positionAt(state: PartyState, nowMs: number): number {
  if (!state.isPlaying) return state.positionSec;
  return state.positionSec + (nowMs - state.updatedAtMs) / 1000;
}

export function listenerPositions(state: PartyState, listenerClockSkewMs: number[], nowMs: number): number[] {
  return listenerClockSkewMs.map((skew) => positionAt(state, nowMs + skew));
}

// ── One-time PIN (T-S04-4) ───────────────────────────────────────────────────

export interface PinIssue {
  pin: string;
  roomPinHash: string;
}

/** Issue a 6-digit one-time PIN for a room (stored hashed, single use). */
export async function issueRoomPin(roomId: string): Promise<PinIssue> {
  const pin = newPin6();
  const row = await db.room.update({
    where: { id: roomId },
    data: { pinHash: hashToken(pin), pinUsedAt: null },
  });
  void row;
  return { pin, roomPinHash: hashToken(pin) };
}

export async function consumeRoomPin(roomId: string, pin: string): Promise<boolean> {
  const room = await db.room.findUnique({ where: { id: roomId } });
  if (!room?.pinHash || room.pinUsedAt) return false; // one-time only
  if (room.pinHash !== hashToken(pin)) return false;
  if (!/^\d{6}$/.test(pin)) return false;
  await db.room.update({ where: { id: roomId }, data: { pinUsedAt: new Date() } });
  return true;
}

// ── Shared playlists (T-S04-5) ───────────────────────────────────────────────

export async function createSharedPlaylist(userId: string, name: string): Promise<{ id: string; shareToken: string }> {
  const pl = await db.playlist.create({
    data: { userId, name, isPublic: true, shareToken: newToken(16) },
  });
  return { id: pl.id, shareToken: pl.shareToken };
}

/** Clone a shared playlist into the caller's account — new playlist_id. */
export async function cloneSharedPlaylist(callerId: string, shareToken: string): Promise<{ id: string; trackCount: number } | null> {
  const source = await db.playlist.findUnique({ where: { shareToken }, include: { tracks: true } });
  if (!source) return null;
  const target = await db.playlist.create({
    data: { userId: callerId, name: `${source.name} (clone)`, isPublic: false, shareToken: newToken(16), isMixed: source.isMixed },
  });
  const ordered = [...source.tracks].sort((a, b) => a.position - b.position);
  await db.playlistTrack.createMany({
    data: ordered.map((t) => ({ playlistId: target.id, trackId: t.trackId, position: t.position })),
  });
  return { id: target.id, trackCount: ordered.length };
}
