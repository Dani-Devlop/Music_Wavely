/**
 * T-S04-1..5, T-R04-1..5 — group features: voice controls, equalizer without
 * interruption, party sync, one-time PIN, shared playlist clone.
 */
import { describe, expect, test } from "bun:test";

describe("S04 voice chat", () => {
  test("T-S04-1 / T-R04-1: all 8 glass-button commands execute and reply", async () => {
    const { voiceCommandReply, VOICE_COMMANDS } = await import("@/lib/wavely/bot/voice-chat");
    let state = { playing: false, preset: "Flat" as const, streamContinuity: true };
    for (const cmd of VOICE_COMMANDS) {
      const { reply, state: next } = voiceCommandReply(cmd, state);
      expect(reply.length).toBeGreaterThan(0);
      state = next;
    }
    expect(state.playing).toBe(false); // ended with /shuffle? no — /shuffle doesn't change playing; /stop does
  });

  test("T-S04-2 / T-R04-2: equalizer preset changes never cut the stream", async () => {
    const { applyEqualizerPreset, EQUALIZER_PRESETS } = await import("@/lib/wavely/bot/voice-chat");
    let state = { playing: true, preset: "Flat" as const, streamContinuity: true };
    for (const preset of EQUALIZER_PRESETS) {
      state = applyEqualizerPreset(state, preset);
      expect(state.streamContinuity).toBe(true); // stream never paused
      expect(state.preset).toBe(preset);
    }
    let threw = false;
    try {
      applyEqualizerPreset(state, "Nonexistent" as never);
    } catch {
      threw = true;
    }
    expect(threw).toBe(true);
  });

  test("T-S04-3 / T-R04-3: two listeners derive identical positions (<100ms drift)", async () => {
    const { positionAt, listenerPositions } = await import("@/lib/wavely/bot/voice-chat");
    const state = { roomId: "r1", trackId: "t1", isPlaying: true, positionSec: 12.5, updatedAtMs: Date.now() - 5000 };
    const positions = listenerPositions(state, [0, 40, -60], Date.now());
    const spread = Math.max(...positions) - Math.min(...positions);
    expect(spread).toBeLessThan(0.1); // <100ms with realistic skews
    expect(positions[0]).toBeGreaterThan(17);
  });

  test("T-S04-4 / T-R04-4: room PIN is 6 digits and strictly one-time", async () => {
    const { db } = await import("@/lib/db");
    const { issueRoomPin, consumeRoomPin } = await import("@/lib/wavely/bot/voice-chat");
    const user = await db.user.create({ data: { email: `room${Date.now()}@wavely.test`, name: "Host" } });
    const room = await db.room.create({ data: { hostUserId: user.id, trackId: "t1" } });
    const { pin } = await issueRoomPin(room.id);
    expect(pin).toMatch(/^\d{6}$/);
    expect(await consumeRoomPin(room.id, pin)).toBe(true);
    expect(await consumeRoomPin(room.id, pin)).toBe(false); // second use rejected
    expect(await consumeRoomPin(room.id, "000000")).toBe(false);
    await db.user.delete({ where: { id: user.id } });
  });

  test("T-S04-5 / T-R04-5: shared playlist clone gets a new id and same tracks", async () => {
    const { db } = await import("@/lib/db");
    const { createSharedPlaylist, cloneSharedPlaylist } = await import("@/lib/wavely/bot/voice-chat");
    const owner = await db.user.create({ data: { email: `share${Date.now()}@wavely.test`, name: "Sharer" } });
    const caller = await db.user.create({ data: { email: `cloner${Date.now()}@wavely.test`, name: "Cloner" } });
    const shared = await createSharedPlaylist(owner.id, "Roadtrip");
    await db.playlistTrack.create({ data: { playlistId: shared.id, trackId: "t01", position: 0 } });
    await db.playlistTrack.create({ data: { playlistId: shared.id, trackId: "t02", position: 1 } });
    const clone = await cloneSharedPlaylist(caller.id, shared.shareToken);
    expect(clone).not.toBeNull();
    expect(clone!.id).not.toBe(shared.id);
    expect(clone!.trackCount).toBe(2);
    const cloneRow = await db.playlist.findUnique({ where: { id: clone!.id } });
    expect(cloneRow?.userId).toBe(caller.id);
    await db.user.deleteMany({ where: { id: { in: [owner.id, caller.id] } } });
  });
});
