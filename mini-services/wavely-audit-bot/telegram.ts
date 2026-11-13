// Telegram Bot API wrapper — token never logged, never embedded in messages.
const TOKEN = process.env.BOT_TOKEN || '';

if (!TOKEN) {
  console.error('[boot] BOT_TOKEN missing in .env — refusing to start');
  process.exit(1);
}

export const OWNER_ID = Number(process.env.OWNER_ID || 0);

interface ApiResult<T = unknown> { ok: boolean; result?: T; description?: string }

function sanitize(text: string): string {
  return text.split(TOKEN).join('<REDACTED>');
}

function log(scope: string, msg: string): void {
  console.log(`[${new Date().toISOString()}] [${scope}] ${sanitize(msg)}`);
}

export async function api<T = unknown>(method: string, body: Record<string, unknown>): Promise<ApiResult<T>> {
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 40_000);
    const res = await fetch(`https://api.telegram.org/bot${TOKEN}/${method}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
      signal: ctrl.signal,
    });
    clearTimeout(timer);
    const json = (await res.json()) as ApiResult<T>;
    if (!json.ok && json.description) log('tg', `${method} failed: ${json.description}`);
    return json;
  } catch (e) {
    log('tg', `${method} error: ${e instanceof Error ? e.message : String(e)}`);
    return { ok: false };
  }
}

export async function sendMessageChunks(chatId: number, parts: string[]): Promise<boolean> {
  let allOk = true;
  for (let i = 0; i < parts.length; i++) {
    const r = await api('sendMessage', {
      chat_id: chatId,
      text: parts[i],
      disable_web_page_preview: true,
    });
    if (!r.ok) allOk = false;
    if (i < parts.length - 1) await new Promise((res) => setTimeout(res, 300));
  }
  return allOk;
}

export async function sendMessage(chatId: number, text: string): Promise<boolean> {
  return sendMessageChunks(chatId, [text]);
}
