// Wavely — Telegram bot webhook (Stage 1.2, task B2).
//
// Receives Telegram updates. Register with BotFather:
//
//   curl "https://api.telegram.org/bot<TOKEN>/setWebhook" \
//     -d "url=<project>.functions.supabase.co/telegram-webhook" \
//     -d "secret_token=<TELEGRAM_WEBHOOK_SECRET>"
//
// Telegram then sends `x-telegram-bot-api-secret-token` on every update —
// validated below against the TELEGRAM_WEBHOOK_SECRET edge secret.
//
// Commands:
//   /start <token>  → calls the telegram-auth edge function (server-to-server
//                     with the service role) and confirms sign-in.
//   /login          → explains the app-side flow.
//   /play /pause /next /queue → Stage 2.2 remote-control stubs.

/** Subset of the Telegram Bot API update shape Wavely consumes. */
interface TelegramChat {
  id: number;
}

interface TelegramFrom {
  id: number;
  username?: string;
  first_name?: string;
}

interface TelegramMessage {
  message_id: number;
  chat: TelegramChat;
  from?: TelegramFrom;
  text?: string;
}

interface TelegramUpdate {
  update_id: number;
  message?: TelegramMessage;
}

/** Typed outgoing message builder (sendMessage payload). */
interface OutgoingMessage {
  chat_id: number;
  text: string;
}

/** Subset of the telegram-auth edge function response. */
interface TelegramAuthResponse {
  email?: string;
  token_hash?: string;
  error?: string;
}

function helpMessage(chatId: number): OutgoingMessage {
  return {
    chat_id: chatId,
    text: [
      '👋 Hi! I am Wavely.',
      '',
      'Tap "Sign in with Telegram" in the Wavely app — it opens this chat',
      'with a one-tap link. Press START and you are signed in.',
      '',
      'Commands: /login · /play · /pause · /next · /queue',
    ].join('\n'),
  };
}

function signedInMessage(chatId: number): OutgoingMessage {
  return { chat_id: chatId, text: '✅ Signed in — return to the app' };
}

function invalidTokenMessage(chatId: number): OutgoingMessage {
  return {
    chat_id: chatId,
    text: '⚠️ This sign-in link is invalid or expired. Open the app and try again.',
  };
}

function stage2StubMessage(chatId: number): OutgoingMessage {
  return { chat_id: chatId, text: '🎵 Remote control arrives in Stage 2.2' };
}

/** Calls the telegram-auth edge function for a /start deep-link token. */
async function exchangeToken(
  token: string,
  from: TelegramFrom,
): Promise<boolean> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authSecret = Deno.env.get('TELEGRAM_AUTH_SECRET');
  if (!supabaseUrl || !serviceKey || !authSecret) return false;

  try {
    const response = await fetch(
      `${supabaseUrl}/functions/v1/telegram-auth`,
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${serviceKey}`,
          'content-type': 'application/json',
          'x-telegram-secret': authSecret,
        },
        body: JSON.stringify({
          token,
          telegram_id: from.id,
          username: from.username,
        }),
      },
    );
    if (!response.ok) return false;
    const data = (await response.json()) as TelegramAuthResponse;
    return typeof data.email === 'string' &&
      typeof data.token_hash === 'string';
  } catch {
    return false;
  }
}

/** Builds the reply for one update (null = nothing to send). */
async function buildReply(
  update: TelegramUpdate,
): Promise<OutgoingMessage | null> {
  const message = update.message;
  if (message === undefined || message.text === undefined) return null;
  const chatId = message.chat.id;
  const [command, ...args] = message.text.trim().split(/\s+/);

  switch (command) {
    case '/start':
      if (args.length === 0) return helpMessage(chatId);
      if (message.from === undefined) return invalidTokenMessage(chatId);
      return (await exchangeToken(args[0], message.from))
        ? signedInMessage(chatId)
        : invalidTokenMessage(chatId);
    case '/login':
      return {
        chat_id: chatId,
        text: 'Open Wavely → Sign in → Sign in with Telegram. The app opens this chat with a one-tap link — no password needed.',
      };
    case '/play':
    case '/pause':
    case '/next':
    case '/queue':
      return stage2StubMessage(chatId);
    default:
      return helpMessage(chatId);
  }
}

async function sendTelegramMessage(message: OutgoingMessage): Promise<void> {
  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN');
  if (!botToken) throw new Error('TELEGRAM_BOT_TOKEN is not set');
  const response = await fetch(
    `https://api.telegram.org/bot${botToken}/sendMessage`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(message),
    },
  );
  if (!response.ok) {
    console.error(`sendMessage failed: ${response.status}`);
  }
}

function timingSafeEqual(a: string | null, b: string | undefined): boolean {
  if (a === null || b === undefined) return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return new Response('POST only', { status: 405 });
  }
  if (
    !timingSafeEqual(
      req.headers.get('x-telegram-bot-api-secret-token'),
      Deno.env.get('TELEGRAM_WEBHOOK_SECRET'),
    )
  ) {
    return new Response('unauthorized', { status: 401 });
  }

  let update: TelegramUpdate;
  try {
    update = (await req.json()) as TelegramUpdate;
  } catch {
    return new Response('invalid JSON body', { status: 400 });
  }

  try {
    const reply = await buildReply(update);
    if (reply !== null) await sendTelegramMessage(reply);
  } catch (error) {
    console.error('webhook handling failed:', error);
  }
  // Always 200 — Telegram retries non-2xx webhooks aggressively.
  return new Response('ok');
});
