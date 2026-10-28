// supabase/functions/telegram-webapp-auth/index.ts
//
// Telegram Mini App initData validation (Stage 2.2).
//
// Validates `initData` per https://core.telegram.org/bots/webapps#validating
// -data-received-via-the-mini-app, then find-or-creates the Supabase user
// for the telegram id and returns a session JWT pair.
//
// SECURITY:
// - The bot token NEVER leaves this function and is NEVER logged.
// - `initData` is NEVER logged (it contains user PII).
// - Data older than 1 hour is rejected (auth_date check).
// - The hash comparison is timing-safe.
// - The client-derived user object is NEVER trusted: identity comes from
//   the HMAC-verified `user` field inside initData only.
// - SEC-2: the mapped account's Supabase password is cryptographically
//   random (never derived from the bot token) and stored only in the
//   deny-all telegram_sessions table (migration 0003). A leaked bot token
//   therefore yields NO usable credentials.
//
// Deploy:
//   supabase functions deploy telegram-webapp-auth \
//     --no-verify-jwt   # the function itself verifies the Telegram HMAC
//   supabase secrets set TELEGRAM_BOT_TOKEN=12345:ABC...
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ONE_HOUR_SECONDS = 60 * 60;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  // Stage 3 audit (SEC-9): a browser preflight for POST + application/json
  // fails without explicit methods — the Mini App webview path needs it.
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface TelegramUser {
  id: number;
  first_name?: string;
  last_name?: string;
  username?: string;
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

function fail(error: string, message: string, status: number): Response {
  return json({ error, message }, status);
}

/** Hex-encodes bytes without allocation-heavy chains. */
function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** HMAC-SHA256 over `key`/`message` returning raw bytes. */
async function hmac(
  key: Uint8Array | string,
  message: string,
): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    typeof key === "string" ? new TextEncoder().encode(key) : key as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(message),
  );
  return new Uint8Array(signature);
}

/** Constant-time equality over equal-length hex strings. */
function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

/** Validates the initData signature + freshness. Returns the user or null. */
async function validateInitData(
  initData: string,
  botToken: string,
): Promise<TelegramUser | null> {
  const params = new URLSearchParams(initData);
  const hash = params.get("hash");
  if (!hash) {
    return null;
  }
  params.delete("hash");
  const dataCheckString = Array.from(params.entries())
    .map(([k, v]) => `${k}=${v}`)
    .sort()
    .join("\n");

  // secret_key = HMAC_SHA256(bot_token, "WebAppData") — Telegram spec.
  const secretKey = await hmac(botToken, "WebAppData");
  const computed = toHex(await hmac(secretKey, dataCheckString));
  if (!timingSafeEqualHex(computed, hash.toLowerCase())) {
    return null;
  }

  // Freshness: auth_date within the last hour.
  const authDate = Number(params.get("auth_date"));
  if (!Number.isFinite(authDate)) {
    return null;
  }
  const nowSeconds = Math.floor(Date.now() / 1000);
  // Stage 3 audit (SEC-19): future-dated auth_date (clock skew attacks) now
  // rejected — the freshness window is symmetric.
  if (
    nowSeconds - authDate > ONE_HOUR_SECONDS ||
    authDate - nowSeconds > 60
  ) {
    return null;
  }

  const rawUser = params.get("user");
  if (!rawUser) {
    return null;
  }
  try {
    const user = JSON.parse(rawUser) as TelegramUser;
    return typeof user.id === "number" ? user : null;
  } catch {
    return null;
  }
}

// SEC-2: the mapped account's password is a cryptographically random value
// generated at provisioning time and stored ONLY in telegram_sessions
// (service-role reachable; deny-all RLS). Nothing is derivable from the bot
// token anymore — a leaked TELEGRAM_BOT_TOKEN no longer yields any user's
// password. Bot-token rotation also no longer invalidates accounts.
function randomPassword(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return toHex(bytes);
}

/** Stable sentinel primary key for the per-user credential mapping row. */
function mappingToken(telegramId: number): string {
  return `telegram-user:${telegramId}`;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return fail("rejected", "POST only.", 405);
  }

  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!botToken || !supabaseUrl || !serviceRoleKey || !anonKey) {
    return fail(
      "misconfigured",
      "Server is missing TELEGRAM_BOT_TOKEN / SUPABASE_* secrets.",
      500,
    );
  }

  let initData = "";
  try {
    const body = await req.json();
    initData = typeof body?.initData === "string" ? body.initData : "";
  } catch {
    return fail("rejected", "Body must be JSON with an initData string.", 400);
  }
  if (!initData) {
    return fail("rejected", "initData is required.", 400);
  }

  const user = await validateInitData(initData, botToken);
  if (user === null) {
    return fail(
      "invalid_signature",
      "initData failed HMAC validation or freshness check.",
      400,
    );
  }

  // Freshness-expired data produces the same validation failure; keep the
  // message coarse on purpose (no oracle about which check failed).
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // SEC-2 credential flow:
  // 1. Look up the stored random password in telegram_sessions and try to
  //    sign in with it (the fast path for returning users).
  // 2. When absent or drifted, provision a FRESH random password via the
  //    admin API (update for a linked user, create otherwise), sign in, and
  //    persist the mapping for future requests.
  // The password is never derivable, never returned to the client, and only
  // ever compared server-side by Supabase auth.
  const email = `${user.id}@telegram.wavely.app`;

  const sessionPayload = (
    session: { access_token: string; refresh_token: string; expires_in: number },
    userId: string | null,
    displayName: string | null,
  ) =>
    json({
      session: {
        access_token: session.access_token,
        refresh_token: session.refresh_token,
        expires_in: session.expires_in,
      },
      user: {
        id: userId,
        display_name: displayName,
      },
    });

  let mapping: {
    token: string;
    password: string | null;
    user_id: string | null;
  } | null = null;
  const mappingSelect = await admin
    .from("telegram_sessions")
    .select("token, password, user_id")
    .eq("telegram_user_id", user.id)
    .maybeSingle();
  if (!mappingSelect.error && mappingSelect.data) {
    mapping = mappingSelect.data;
  }

  if (mapping?.password) {
    const signIn = await admin.auth.signInWithPassword({
      email,
      password: mapping.password,
    });
    if (!signIn.error && signIn.data.session) {
      return sessionPayload(
        signIn.data.session,
        signIn.data.user?.id ?? mapping.user_id,
        signIn.data.user?.user_metadata?.display_name ?? null,
      );
    }
    // Stored credential drifted (manual password change, partial restore) —
    // fall through and provision a fresh one.
  }

  const password = randomPassword();
  let userId: string | null = mapping?.user_id ?? null;

  const provisionFailed = () =>
    fail(
      "rejected",
      "Telegram identity is valid but the mapped account could not be " +
        "provisioned. Contact the operator.",
      401,
    );

  if (userId) {
    const updated = await admin.auth.admin.updateUserById(userId, {
      password,
    });
    if (updated.error) {
      // Stale mapping (account deleted server-side) — fall back to
      // find-or-create below.
      userId = null;
    }
  }

  if (!userId) {
    const link = await admin
      .from("telegram_links")
      .select("user_id")
      .eq("telegram_id", user.id)
      .maybeSingle();
    if (!link.error && link.data?.user_id) {
      const updated = await admin.auth.admin.updateUserById(
        link.data.user_id as string,
        { password },
      );
      if (updated.error) {
        return provisionFailed();
      }
      userId = link.data.user_id as string;
    } else {
      const created = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          telegram_id: user.id,
          username: user.username ?? null,
          display_name:
            [user.first_name, user.last_name].filter(Boolean).join(" ") ||
            user.username ||
            `telegram-${user.id}`,
        },
      });
      if (created.error || !created.data.user) {
        return provisionFailed();
      }
      userId = created.data.user.id;
    }
  }

  const signIn = await admin.auth.signInWithPassword({ email, password });
  if (signIn.error || !signIn.data.session) {
    return fail("rejected", "Could not establish a session.", 401);
  }

  // Persist the credential mapping (best effort AFTER the session exists —
  // a mapping write failure only costs a re-provision on the next request).
  await admin.from("telegram_sessions").upsert(
    {
      token: mappingToken(user.id),
      telegram_user_id: user.id,
      user_id: userId,
      email,
      password,
      used: false,
    },
    { onConflict: "token" },
  );

  return sessionPayload(
    signIn.data.session,
    signIn.data.user?.id ?? userId,
    signIn.data.user?.user_metadata?.display_name ?? null,
  );
});
