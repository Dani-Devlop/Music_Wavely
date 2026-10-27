# Supabase setup — Wavely Stage 1.2

Auth (email + Telegram bot link) and sync run on Supabase. Everything is
**optional**: without `SUPABASE_URL`/`SUPABASE_ANON_KEY` the app stays a
fully-functional local player (auth screens render a "disabled" state, the
sync engine idles in `disabled`).

## 1. Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli) ≥ 1.150
- A Telegram bot (BotFather) — for Telegram sign-in only
- Docker (local dev) or a Supabase cloud project

## 2. Local project

```bash
cd Music_Wavely
supabase init                  # creates supabase/ scaffolding (config.toml is committed)
supabase start                 # boots local stack (postgres, auth, edge runtime)
supabase db reset              # applies supabase/migrations/0001_init.sql
```

`0001_init.sql` creates: `profiles`, `devices`, `user_settings`, `plays`,
`track_stats_daily`, `artist_follows`, `sync_state`, `telegram_links`,
`telegram_sessions`; the `redeem_telegram_session(...)` RPC (security
definer, granted to `anon`); the `auth.users` → `profiles`+`user_settings`
trigger; and RLS (`user_id = auth.uid()`, profiles `id = auth.uid()`) on
every table.

## 3. Edge functions (Telegram auth)

```bash
supabase functions serve telegram-auth --env-file ./supabase/.env.local
supabase functions serve telegram-webhook --env-file ./supabase/.env.local
```

Required secrets (`supabase secrets set` or the local env file):

| Secret | Purpose |
|---|---|
| `TELEGRAM_AUTH_SECRET` | shared secret between bot webhook and `telegram-auth` |
| `TELEGRAM_WEBHOOK_SECRET` | Telegram's `X-Telegram-Bot-Api-Secret-Token` |
| `SUPABASE_SERVICE_ROLE_KEY` | admin user creation inside the function (never shipped to the app) |
| `TELEGRAM_BOT_TOKEN` | bot API calls from the webhook |

Auth flow (documented honestly): the app mints a UUID token → opens
`t.me/<bot>?start=<token>` → the bot webhook calls `telegram-auth`, which
finds-or-creates the auth user + profile and returns a magic-link
`token_hash` → the bot replies "signed in" → the app polls
`redeem_telegram_session(<token>)` (every 2 s, ≤5 min) and completes sign-in
with `supabase.auth.verifyOtp(type: magiclink, email, tokenHash)`.

## 4. Telegram bot wiring

1. `@BotFather` → `/newbot` → copy token.
2. `/setcommands` → add `start`, `login`, `play`, `pause`, `next`, `queue`.
3. Point the webhook (cloud only):

```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=https://<project>.supabase.co/functions/v1/telegram-webhook" \
  -d "secret_token=<TELEGRAM_WEBHOOK_SECRET>"
```

## 5. App configuration (compile-time env)

Copy `.env.example` → `.env`, fill in, then run with dart-defines (NO asset
loading, `.env` stays uncommitted):

```bash
flutter run  --dart-define-from-file=.env
flutter test --dart-define-from-file=.env
```

Keys consumed by Stage 1.2: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`TELEGRAM_BOT_USERNAME`, `GEMINI_API_KEY` / `OPENAI_API_KEY` (AI DJ),
`SPOTIFY_CLIENT_ID` (metadata adapter), `JAMENDO_CLIENT_ID` (Stage 2.1).

## 6. RLS summary

| Table | SELECT / INSERT / UPDATE / DELETE |
|---|---|
| `profiles` | `id = auth.uid()` |
| everything else | `user_id = auth.uid()` |
| `telegram_sessions` | **no** client access — RPC + service role only |

## 7. Verification checklist (owner)

```bash
supabase db reset                      # migration applies clean
supabase functions serve ...           # both functions boot
# sign up via the app → profiles + user_settings rows exist (trigger fired)
# telegram /start <token> → session lands, app signs in
# play a track offline → plays row lands in outbox → pushes when online
```
