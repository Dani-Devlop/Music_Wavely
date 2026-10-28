-- 0003_telegram_user_passwords.sql — Stage 3 final polish (SEC-2).
--
-- Problem: the Telegram Mini App edge function (telegram-webapp-auth) used
-- to derive every mapped user's Supabase password deterministically from
-- the bot token (hmac(botToken, 'wavely-telegram-user:<id>')). The scheme
-- is public in this repo and SUPABASE_URL is public, so a leaked
-- TELEGRAM_BOT_TOKEN let an attacker compute ANY user's password and sign
-- in directly, bypassing the edge function's HMAC gate.
--
-- Fix: the edge function now provisions a cryptographically random
-- password (crypto.getRandomValues) per user and stores the mapping ONLY
-- in this table. The columns below carry the credential mapping:
--   telegram_user_id  the verified Telegram id (synthetic rows, one per user)
--   password          the random Supabase password (never derivable, never
--                     returned to clients, only compared server-side)
-- Synthetic mapping rows are keyed by the existing PRIMARY KEY `token` with
-- the stable sentinel value 'telegram-user:<id>' so the mini-app flow and
-- the Stage 1.2 pending-token rows never collide (pending rows always carry
-- a random token + expires_at; mapping rows carry NULL expires_at).
--
-- Access surface is unchanged and stays deny-all: RLS enabled with no
-- policies, and `revoke all ... from anon, authenticated` (0001_init.sql
-- §13) — reachable only via the service role (the edge function) or the
-- security-definer redeem_telegram_session(), which reads neither column.

alter table public.telegram_sessions
  add column if not exists telegram_user_id bigint,
  add column if not exists password text;

-- Lookup path of the edge function (`where telegram_user_id = $1`).
create index if not exists telegram_sessions_telegram_user_id_idx
  on public.telegram_sessions (telegram_user_id)
  where telegram_user_id is not null;
