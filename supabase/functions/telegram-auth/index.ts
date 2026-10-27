// Wavely — Telegram sign-in exchange edge function (Stage 1.2, task B2).
//
// Two-step magic-link flow (reconciled; see docs/SUPABASE_SETUP.md):
//
//  1. The app generates a one-time token (uuid v4) and opens
//     `https://t.me/<bot>?start=<token>`. The bot forwards
//     `{token, telegram_id, username}` here (server-to-server).
//  2. This function maps the Telegram identity to a Supabase user
//     (find-or-create), then calls admin.generateLink({type:'magiclink'}).
//     generateLink does NOT e-mail anyone — it returns the action link whose
//     `properties.hashed_token` is exactly what auth.verifyOTP(tokenHash:)
//     needs. IMPORTANT: hashed_token is NOT a JWT. There is no admin API
//     that mints a session JWT directly (signInWithIdToken is third-party
//     OIDC only), so the CLIENT must call verifyOTP with this token hash to
//     obtain the real session — that is the documented, supported flow.
//  3. The function stores {email, token_hash} beside the token in
//     telegram_sessions (5-minute TTL) and returns {email, token_hash}.
//  4. The bot replies "✅ Signed in — return to the app"; the app polls the
//     security-definer SQL function redeem_telegram_session(token), which
//     atomically marks the row used and hands back {email, token_hash}, then
//     finishes sign-in with supabase.auth.verifyOTP.
//
// Secret: the caller must send `x-telegram-secret` matching the
// TELEGRAM_AUTH_SECRET edge secret (`supabase secrets set`). The comparison
// below is a best-effort constant-time compare, NOT audited cryptography —
// rotate the secret if it ever leaks.

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const TELEGRAM_EMAIL_DOMAIN = 'telegram.wavely.local';
const SESSION_TTL_MINUTES = 5;

/** POST body sent by the Telegram webhook. */
interface TelegramAuthRequest {
  token: string;
  telegram_id: number;
  username?: string;
}

/** Payload stored beside the token and returned to the caller. */
interface RedeemRow {
  email: string;
  token_hash: string;
}

const corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers':
    'authorization, x-client-info, apikey, content-type, x-telegram-secret',
  'access-control-allow-methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}

/** Best-effort constant-time string comparison (not audited crypto). */
function timingSafeEqual(a: string | null, b: string | undefined): boolean {
  if (a === null || b === undefined) return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/** Service-role client (bypasses RLS; never exposed to the app). */
function adminClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) {
    throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are not set');
  }
  return createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/** Deterministic placeholder e-mail keyed by the Telegram id. */
function telegramEmail(telegramId: number): string {
  return `${telegramId}@${TELEGRAM_EMAIL_DOMAIN}`;
}

function isAlreadyRegistered(error: { code?: string; message?: string }): boolean {
  return (
    error.code === 'email_exists' ||
    (error.message ?? '').includes('already been registered')
  );
}

/** Find-or-create the auth user for the Telegram identity and mint a magic
 * link. Never sends an e-mail — generateLink only mints the token hash. */
async function mintMagicLink(
  admin: SupabaseClient,
  request: TelegramAuthRequest,
): Promise<RedeemRow> {
  const email = telegramEmail(request.telegram_id);

  let link = await admin.auth.admin.generateLink({ type: 'magiclink', email });
  if (link.error !== null) {
    // The auth user probably does not exist yet — create it, then retry once.
    const created = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      // Password is never used; sign-in is magic-link only.
      password: crypto.randomUUID(),
      user_metadata: {
        telegram_id: request.telegram_id,
        username: request.username ?? null,
      },
    });
    if (created.error !== null && !isAlreadyRegistered(created.error)) {
      throw new Error(`createUser failed: ${created.error.message}`);
    }
    link = await admin.auth.admin.generateLink({ type: 'magiclink', email });
    if (link.error !== null) {
      throw new Error(`generateLink failed: ${link.error.message}`);
    }
  }

  const userId = link.data.user?.id;
  const tokenHash = link.data.properties?.hashed_token;
  if (!userId || !tokenHash) {
    throw new Error('generateLink returned no user or token hash');
  }

  // Safety net for users created before the profile trigger existed.
  const { error: profileError } = await admin
    .from('profiles')
    .upsert(
      { id: userId, display_name: request.username ?? null },
      { onConflict: 'id', ignoreDuplicates: true },
    );
  if (profileError !== null) {
    throw new Error(`profiles upsert failed: ${profileError.message}`);
  }

  const { error: linkError } = await admin
    .from('telegram_links')
    .upsert(
      { telegram_id: request.telegram_id, user_id: userId },
      { onConflict: 'telegram_id' },
    );
  if (linkError !== null) {
    throw new Error(`telegram_links upsert failed: ${linkError.message}`);
  }

  return { email, token_hash: tokenHash };
}

/** (Re-)arms the one-time session row for the app-generated token. */
async function storeSession(
  admin: SupabaseClient,
  token: string,
  row: RedeemRow,
): Promise<void> {
  const expiresAt = new Date(
    Date.now() + SESSION_TTL_MINUTES * 60_000,
  ).toISOString();
  const { error } = await admin.from('telegram_sessions').upsert(
    {
      token,
      email: row.email,
      token_hash: row.token_hash,
      expires_at: expiresAt,
      used: false,
    },
    { onConflict: 'token' },
  );
  if (error !== null) {
    throw new Error(`telegram_sessions upsert failed: ${error.message}`);
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'POST only' }, 405);
  }

  const secret = Deno.env.get('TELEGRAM_AUTH_SECRET');
  if (!timingSafeEqual(req.headers.get('x-telegram-secret'), secret)) {
    return json({ error: 'unauthorized' }, 401);
  }

  let request: TelegramAuthRequest;
  try {
    request = (await req.json()) as TelegramAuthRequest;
  } catch {
    return json({ error: 'invalid JSON body' }, 400);
  }
  if (
    typeof request.token !== 'string' ||
    request.token.length === 0 ||
    typeof request.telegram_id !== 'number'
  ) {
    return json({ error: 'token and telegram_id are required' }, 400);
  }

  try {
    const admin = adminClient();
    const row = await mintMagicLink(admin, request);
    await storeSession(admin, request.token, row);
    return json({ email: row.email, token_hash: row.token_hash });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : 'internal error' },
      500,
    );
  }
});
