/**
 * S09 / S10 / S14 / R09 / R10 / R14 — bot command registry.
 * Public commands, group commands, social commands, AI DJ commands and the
 * owner-only /admin panel. Language flow (/start with 5 languages) and the
 * force-join gate live here.
 */
import { db } from "@/lib/db";
import { OWNER_ID } from "../server/env";
import { getFlag, FLAG_KEYS } from "./flags";

export { FLAG_KEYS };

export const BOT_LANGUAGES = ["English", "فارسی", "Русский", "العربية", "Türkçe"] as const;
export type BotLanguage = (typeof BOT_LANGUAGES)[number];

export const FORCE_JOIN_CHANNEL = "https://t.me/My_Hellz";

export interface BotUserRef {
  id: string; // telegram user id as string
  first_name?: string;
  last_name?: string;
  username?: string;
}

export interface CommandContext {
  from: BotUserRef;
  chatId: string;
  isGroup: boolean;
  args?: string;
}

export interface CommandReply {
  text: string;
  buttons?: { label: string; data: string }[];
}

export const PUBLIC_COMMANDS = ["/start", "/help", "/contact", "/dmca", "/privacy", "/me", "/lang", "/settings"] as const;
export const GROUP_COMMANDS = ["/play", "/pause", "/resume", "/skip", "/stop", "/queue", "/loop", "/shuffle"] as const;
export const SOCIAL_COMMANDS = ["/new_room", "/join_room"] as const;
export const DJ_COMMANDS = ["/dj", "/dj_play", "/dj_stop"] as const;

// ── /start flow (S10) ────────────────────────────────────────────────────────

/** New user → language menu with 5 buttons (T-S09-1). */
export async function handleStart(ctx: CommandContext): Promise<CommandReply> {
  const row = await db.user.findUnique({ where: { telegramId: ctx.from.id } });
  if (!row) {
    return {
      text: "Welcome to Wavely! Choose your language:",
      buttons: BOT_LANGUAGES.map((l) => ({ label: l, data: `lang:${l}` })),
    };
  }
  // returning user → straight welcome in the stored language (T-S09-2)
  return { text: welcomeIn(row.language) };
}

function welcomeIn(language: string): string {
  const map: Record<string, string> = {
    en: "Welcome back to Wavely — tap the button below to open the mini app.",
    fa: "به Wavely خوش آمدید — برای باز شدن مینی‌اپ دکمه زیر را بزنید.",
    ru: "С возвращением в Wavely — нажмите кнопку ниже, чтобы открыть мини-приложение.",
    ar: "مرحبًا بعودتك إلى Wavely — اضغط الزر أدناه لفتح التطبيق المصغّر.",
    tr: "Wavely'ye geri döndünüz — mini uygulamayı açmak için aşağıdaki düğmeye dokunun.",
  };
  return map[language] ?? map.en;
}

/** Language selection callback — save + apply immediately (T-S10-1). */
export async function handleLanguageChoice(userId: string, language: BotLanguage): Promise<CommandReply> {
  const code = languageCode(language);
  await db.user.upsert({
    where: { telegramId: userId },
    create: { telegramId: userId, language: code, name: "Telegram user", email: `${userId}@telegram.wavely.local` },
    update: { language: code },
  });
  return { text: `${welcomeIn(code)} (language: ${language})` };
}

export function languageCode(language: BotLanguage): string {
  const map: Record<BotLanguage, string> = {
    English: "en",
    "فارسی": "fa",
    "Русский": "ru",
    "العربية": "ar",
    "Türkçe": "tr",
  };
  return map[language];
}

export const SUPPORTED_LANGUAGES = ["en", "fa", "ru", "ar", "tr"] as const;

/** /lang — reopen the menu. */
export async function handleLang(ctx: CommandContext): Promise<CommandReply> {
  return {
    text: "Choose your language:",
    buttons: BOT_LANGUAGES.map((l) => ({ label: l, data: `lang:${l}` })),
  };
}

// ── /me (T-S09-3: no empty last_name line) ───────────────────────────────────

export function meProfileText(from: BotUserRef, language?: string, email?: string | null): string {
  const lines: string[] = [];
  lines.push(`Name: ${from.first_name ?? "—"}`);
  if (from.last_name && from.last_name.trim().length > 0) lines.push(`Last name: ${from.last_name}`); // omitted entirely when empty
  if (from.username) lines.push(`Username: @${from.username}`);
  if (email) lines.push(`Email: ${email}`);
  if (language) lines.push(`Language: ${language}`);
  return lines.join("\n");
}

// ── /admin (T-S09-5: owner-only, ID from env) ────────────────────────────────

export async function handleAdmin(ctx: CommandContext): Promise<CommandReply> {
  if (ctx.from.id !== OWNER_ID) {
    return { text: "This command is only available to the bot owner." };
  }
  return {
    text: "Owner panel:",
    buttons: [
      { label: "Force Join", data: "admin:forcejoin" },
      { label: "Broadcast", data: "admin:broadcast" },
      { label: "User Stats", data: "admin:stats" },
      { label: "Settings", data: "admin:settings" },
      { label: "Provider Management", data: "admin:providers" },
      { label: "Feature Flags", data: "admin:flags" },
    ],
  };
}

/** Only the owner may flip feature flags (T-S08-3). */
export async function adminSetFlag(userId: string, key: FlagKey, value: string): Promise<CommandReply> {
  if (userId !== OWNER_ID) return { text: "Forbidden — owner only." };
  const { setFlag } = await import("./flags");
  await setFlag(key, value);
  return { text: `Flag ${key} → ${value}` };
}

// ── Force join (S14) ─────────────────────────────────────────────────────────

/** Gate applied before every command. Default OFF (T-S14-1). */
export async function forceJoinGate(ctx: CommandContext): Promise<CommandReply | null> {
  const enabled = (await getFlag(FLAG_KEYS.forceJoin)) === "true";
  if (!enabled) return null;
  const user = await db.user.findUnique({ where: { telegramId: ctx.from.id } });
  const joined = user?.emailVerified ?? false; // membership flag proxy in prototype
  if (joined) return null;
  return {
    text: `Please join our channel first: ${FORCE_JOIN_CHANNEL}`,
    buttons: [
      { label: "Join channel", data: `join:${FORCE_JOIN_CHANNEL}` },
      { label: "I joined", data: "join:check" },
    ],
  };
}

// ── Dispatcher ───────────────────────────────────────────────────────────────

export async function dispatchCommand(ctx: CommandContext, raw: string): Promise<CommandReply> {
  const cmd = raw.trim().split(/\s+/)[0].toLowerCase();
  const gate = await forceJoinGate(ctx);
  if (gate) return gate;

  switch (cmd) {
    case "/start":
      return handleStart(ctx);
    case "/lang":
      return handleLang(ctx);
    case "/me":
      return { text: meProfileText(ctx.from) };
    case "/admin":
      return handleAdmin(ctx);
    case "/help":
      return { text: `Commands: ${[...PUBLIC_COMMANDS, ...GROUP_COMMANDS, ...SOCIAL_COMMANDS, ...DJ_COMMANDS].join(" ")}` };
    case "/contact":
      return { text: "Contact: @WavelySupport" };
    case "/dmca":
      return { text: "DMCA: dmca@wavely.app" };
    case "/privacy":
      return { text: "Privacy: we store only what Wavely needs to play your music. Full policy at /privacy in the mini app." };
    case "/settings":
      return { text: "Open Settings from the mini app — audio quality, downloads, captions, cache." };
    default:
      if ((GROUP_COMMANDS as readonly string[]).includes(cmd)) return { text: `${cmd} acknowledged` };
      if ((SOCIAL_COMMANDS as readonly string[]).includes(cmd)) return { text: `${cmd} acknowledged` };
      if ((DJ_COMMANDS as readonly string[]).includes(cmd)) {
        const { handleDjCommand } = await import("./ai-dj");
        return handleDjCommand(ctx, raw.trim());
      }
      return { text: "Unknown command — try /help" };
  }
}
