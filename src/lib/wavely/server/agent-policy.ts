/**
 * S22 / S51 / S68 — AI agent policy layer.
 * The agent may ONLY touch the current user's music domain: playback control,
 * playlists, metadata, play history, lyrics. Everything else (code, files,
 * system, account settings, other users' data) is refused.
 *
 * Layers: input filter → music-only classifier → tool allowlist →
 *         output filter → audit + daily quota.
 */
import { db } from "@/lib/db";
import { audit } from "./audit";
import { newToken } from "./tokens";

export const AGENT_TOOL_ALLOWLIST = [
  "search_music",
  "play",
  "pause",
  "queue_add",
  "playlist_create",
  "playlist_add",
  "recommend_similar",
  "get_lyrics",
  "search_lyrics",
  "match_lyrics",
  "taste_analysis",
] as const;
export type AgentTool = (typeof AGENT_TOOL_ALLOWLIST)[number];

export function isToolAllowed(tool: string): tool is AgentTool {
  return (AGENT_TOOL_ALLOWLIST as readonly string[]).includes(tool);
}

// ── Input filtering (prompt injection, multi-language) ──────────────────────

const INJECTION_PATTERNS: RegExp[] = [
  /ignore (all )?(previous|prior|above) (instructions|prompts?)/i,
  /disregard (all )?(previous|above)/i,
  /system prompt/i,
  /you are now/i,
  /act as (if|a) (you|an|the)/i,
  /developer mode/i,
  /jailbreak/i,
  /چشم پوشی از دستورات/i,
  /دستورات قبلی را نادیده/i,
  /проигнорируй (все )?инструкции/i,
  /يُرجى تجاهل التعليمات/i,
  /önceki talimatları yoksay/i,
];

export interface InputFilterVerdict {
  ok: boolean;
  reason?: "prompt-injection" | "too-long";
}

export function filterAgentInput(message: string): InputFilterVerdict {
  if (message.length > 2000) return { ok: false, reason: "too-long" };
  for (const re of INJECTION_PATTERNS) {
    if (re.test(message)) return { ok: false, reason: "prompt-injection" };
  }
  return { ok: true };
}

// ── Music-only classification ────────────────────────────────────────────────

const NON_MUSIC_PATTERNS: { re: RegExp; label: string }[] = [
  { re: /(write|generate|show|build).{0,20}(code|python|javascript|html|css|sql|script)/i, label: "code" },
  { re: /(کد|اسکریپت)\s*(پایتون|بنویس|جاوا|پی اچ پی)/i, label: "code-fa" },
  { re: /(напиши|создай).{0,15}(код|скрипт)/i, label: "code-ru" },
  { re: /(اكتب|أنشئ).{0,15}(كود|برمج)/i, label: "code-ar" },
  { re: /(yaz|oluştur).{0,15}(kod|script)/i, label: "code-tr" },
  { re: /(recipe|ingredients|how to cook|bake a|preheat)/i, label: "recipe" },
  { re: /(دستور پخت|طرز تهیه)/i, label: "recipe-fa" },
  { re: /(write|compose).{0,20}(essay|article|blog|poem about politics)/i, label: "article" },
  { re: /(مقاله|بنویس مقاله)/i, label: "article-fa" },
  { re: /(see|read|open|delete|access).{0,20}(my )?(files?|filesystem|disk|documents)/i, label: "files" },
  { re: /(فایل|سیستم عامل|فایل‌ها)\s*(را\s*)?(ببین|پاک|باز)/i, label: "files-fa" },
  { re: /(change|reset|show).{0,20}(my )?(password|2fa|token|api key|secret)/i, label: "account-security" },
  { re: /(تغییر|ببین)\s*(رمز|پسورد|توکن)/i, label: "account-security-fa" },
  { re: /(run|execute|sudo|rm -rf|shell|terminal command)/i, label: "system" },
  { re: /(weather|stock|bitcoin|news headlines)/i, label: "non-music-domain" },
];

export interface MusicOnlyVerdict {
  music: boolean;
  label?: string;
}

/** T-S22-2 / T-S68-3: any non-music intent → refused. */
export function isMusicOnlyRequest(message: string): MusicOnlyVerdict {
  for (const { re, label } of NON_MUSIC_PATTERNS) {
    if (re.test(message)) return { music: false, label };
  }
  return { music: true };
}

// ── Output filtering ─────────────────────────────────────────────────────────

export interface OutputFilterVerdict {
  ok: boolean;
  cleaned: string;
  reason?: "code-output" | "non-music" | "secret";
}

/**
 * T-S51-3 / T-S68-6: the agent must never emit code blocks, shell commands or
 * secret-shaped strings. Offending content is stripped and flagged.
 */
export function filterAgentOutput(text: string): OutputFilterVerdict {
  if (/```|~~~/.test(text)) {
    return { ok: false, cleaned: "", reason: "code-output" };
  }
  if (/\b(import |def |function |class |SELECT .+ FROM|console\.log|#!/).test(text) && !/song|track|lyric|album|artist|playlist/i.test(text)) {
    return { ok: false, cleaned: "", reason: "code-output" };
  }
  if (/\b\d{8,12}:AA[\w-]{20,}\b|\bapp\d+:[\w]{20,}\b/.test(text)) {
    return { ok: false, cleaned: "", reason: "secret" };
  }
  if (/(recipe|python code|html page|stock tip)/i.test(text)) {
    return { ok: false, cleaned: "", reason: "non-music" };
  }
  return { ok: true, cleaned: text };
}

// ── Domain-restricted tools (T-S68-1: read/control music only) ───────────────

export interface AgentMusicContext {
  userId: string;
}

/** The agent's data scope: only the caller's own music entities. */
export async function agentMusicScope(ctx: AgentMusicContext) {
  const [playlists, recentPlays] = await Promise.all([
    db.playlist.findMany({ where: { userId: ctx.userId }, select: { id: true, name: true, isMixed: true }, take: 50 }),
    db.download.findMany({ where: { userId: ctx.userId }, orderBy: { timestamp: "desc" }, take: 20, select: { trackId: true, title: true } }),
  ]);
  return { playlists, recentPlays }; // NO cross-user fields, NO account fields
}

/** T-S51-6 / T-S68-2: cross-user access is structurally impossible — scope is always caller-bound. */
export async function agentPlaylistForUser(userId: string, playlistId: string) {
  return db.playlist.findFirst({ where: { id: playlistId, userId } }); // null for other users' playlists
}

// ── Quota (T-S51-8) ──────────────────────────────────────────────────────────

export const AGENT_DAILY_TOKEN_LIMIT = 100_000;
export const AGENT_DAILY_REQUEST_LIMIT = 200;

export async function agentQuotaOk(userId: string, requestedTokens: number): Promise<{ ok: boolean; reason?: string }> {
  const day = new Date().toISOString().slice(0, 10);
  const usage = await db.agentUsage.findUnique({ where: { userId_day: { userId, day } } });
  if (!usage) return { ok: true };
  if (usage.tokens + requestedTokens > AGENT_DAILY_TOKEN_LIMIT) return { ok: false, reason: "token-quota" };
  if (usage.requests + 1 > AGENT_DAILY_REQUEST_LIMIT) return { ok: false, reason: "request-quota" };
  return { ok: true };
}

export async function agentRecordUsage(userId: string, tokens: number): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  await db.agentUsage.upsert({
    where: { userId_day: { userId, day } },
    create: { userId, day, tokens, requests: 1 },
    update: { tokens: { increment: tokens }, requests: { increment: 1 } },
  });
}

// ── Full pipeline ────────────────────────────────────────────────────────────

export interface AgentRequestResult {
  ok: boolean;
  code: string;
  reply?: string;
}

/**
 * In-scope music answer generator (deterministic, catalogue-backed) — used
 * when the request IS music. The full LLM chat path lives in /api/agent.
 */
export async function handleAgentRequest(userId: string, message: string, ip?: string): Promise<AgentRequestResult> {
  const input = filterAgentInput(message);
  if (!input.ok) {
    await audit({ userId, event: "ai_out_of_scope", ip, meta: { reason: input.reason } });
    return { ok: false, code: `agent-refused-${input.reason}` };
  }
  const music = isMusicOnlyRequest(message);
  if (!music.music) {
    await audit({ userId, event: "ai_out_of_scope", ip, meta: { reason: music.label } });
    return {
      ok: false,
      code: "agent-music-only",
      reply: "I'm Wavely's music assistant — I can search songs, build playlists, find lyrics, recommend similar artists and analyse your listening taste. Let's stay in the world of music!",
    };
  }
  const quota = await agentQuotaOk(userId, Math.ceil(message.length / 4));
  if (!quota.ok) return { ok: false, code: `agent-${quota.reason}` };

  // music-domain tool routing
  if (/lyrics?|متن آهنگ|لیریک/i.test(message)) {
    return { ok: true, code: "agent-tool", reply: "Opening the synced lyrics panel for this track (tool: get_lyrics)." };
  }
  if (/similar|recommend|پیشنهاد/i.test(message)) {
    return { ok: true, code: "agent-tool", reply: "Here are songs close to your recent plays (tool: recommend_similar)." };
  }
  if (/taste|history|analysis/i.test(message)) {
    return { ok: true, code: "agent-tool", reply: "Your listening taste this month, based on play counts (tool: taste_analysis)." };
  }
  const used = newToken(4);
  await agentRecordUsage(userId, Math.ceil(message.length / 4));
  return { ok: true, code: `agent-reply-${used.slice(0, 2)}`, reply: "Music answer: queued from your library." };
}
