/**
 * S01 / S08 / R01 / R08 — bot feature flags, backed by the bot_config table.
 * The three AI capabilities are disabled by default and can only be flipped
 * from /admin (owner) via the admin endpoint.
 */
import { db } from "@/lib/db";

export const FLAG_KEYS = {
  aiSearch: "ai_search_enabled",
  audioRecognition: "audio_recognition_enabled",
  aiDjPersonalization: "ai_dj_personalization_enabled",
  activeMusicProvider: "active_music_provider",
  forceJoin: "force_join_enabled",
} as const;

export type FlagKey = (typeof FLAG_KEYS)[keyof typeof FLAG_KEYS];

const DEFAULTS: Record<string, string> = {
  [FLAG_KEYS.aiSearch]: "false", // S08: disabled
  [FLAG_KEYS.audioRecognition]: "false", // S08: disabled
  [FLAG_KEYS.aiDjPersonalization]: "false", // S07-2: disabled
  [FLAG_KEYS.activeMusicProvider]: "jamendo", // S13
  [FLAG_KEYS.forceJoin]: "false", // S14: default off
};

export async function getFlag(key: FlagKey): Promise<string> {
  const row = await db.botConfig.findUnique({ where: { key } });
  if (!row) return DEFAULTS[key] ?? "";
  return row.value;
}

export async function setFlag(key: FlagKey, value: string): Promise<void> {
  await db.botConfig.upsert({ where: { key }, create: { key, value }, update: { value } });
}

/** Idempotently seed every default flag row into bot_config. */
export async function ensureFlagDefaults(): Promise<void> {
  for (const [key, value] of Object.entries(DEFAULTS)) {
    await db.botConfig.upsert({ where: { key }, create: { key, value }, update: {} });
  }
}

/** All AI flags default false (T-S01-3 / T-S08-2). */
export async function aiFlagsAllFalse(): Promise<{ ai_search: boolean; audio_recognition: boolean; ai_dj_personalization: boolean }> {
  return {
    ai_search: (await getFlag(FLAG_KEYS.aiSearch)) === "true",
    audio_recognition: (await getFlag(FLAG_KEYS.audioRecognition)) === "true",
    ai_dj_personalization: (await getFlag(FLAG_KEYS.aiDjPersonalization)) === "true",
  };
}

/**
 * S08-1: modules must never load without their flag.
 * The gated module registry returns null unless the flag is enabled — this is
 * the ONLY way bot code may reach these modules.
 */
export interface GatedModules {
  aiSearch: { search: (q: string) => Promise<string[]> } | null;
  audioRecognize: { recognize: (sampleId: string) => Promise<string | null> } | null;
  aiDjPersonalization: { personalize: (userId: string) => Promise<string[]> } | null;
}

/* Gated module implementations — inert until their flag is true. */
const aiSearchModule = {
  search: async (q: string): Promise<string[]> => [`ai-result:${q}`],
};
const audioRecognizeModule = {
  recognize: async (sampleId: string): Promise<string | null> => `match:${sampleId}`,
};
const aiDjPersonalizationModule = {
  personalize: async (userId: string): Promise<string[]> => [`personal-mix:${userId}`],
};

export async function loadGatedModules(): Promise<GatedModules> {
  return {
    aiSearch: (await getFlag(FLAG_KEYS.aiSearch)) === "true" ? aiSearchModule : null,
    audioRecognize: (await getFlag(FLAG_KEYS.audioRecognition)) === "true" ? audioRecognizeModule : null,
    aiDjPersonalization: (await getFlag(FLAG_KEYS.aiDjPersonalization)) === "true" ? aiDjPersonalizationModule : null,
  };
}
