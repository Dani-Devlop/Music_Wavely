-- Wavely Stage 1.2 — initial schema (task B2).
--
-- Idempotent by construction: `create ... if not exists` DDL, `drop policy
-- if exists` + recreate for RLS, plain grants/revokes. Safe with
-- `supabase db reset` and safe to re-run on a partially migrated database.
--
-- Layout:
--   1. extension          uuid-ossp
--   2. profiles           one row per auth user (trigger-created)
--   3. devices            registered playback devices
--   4. user_settings      per-user settings mirror (jsonb blob)
--   5. plays              raw play events (deduped per fingerprint+start)
--   6. track_stats_daily  pre-aggregated daily stats
--   7. artist_follows     followed artists
--   8. sync_state         per-device pull/push cursors
--   9. telegram_links     telegram identity -> profile mapping (edge-owned)
--  10. telegram_sessions  one-time sign-in tokens minted by the edge fn
--  11. handle_new_user()  trigger on auth.users
--  12. redeem_telegram_session(token)  security-definer one-time redeem
--  13. RLS policies + grants
--  14. indexes

-- ── 1. Extension ─────────────────────────────────────────────────────────────

create extension if not exists "uuid-ossp";

-- ── 2. profiles ──────────────────────────────────────────────────────────────

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ── 3. devices ───────────────────────────────────────────────────────────────

create table if not exists public.devices (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  device_name text not null,
  last_seen_at timestamptz not null default now(),
  unique (user_id, device_name)
);

-- ── 4. user_settings ─────────────────────────────────────────────────────────

create table if not exists public.user_settings (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  settings jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

-- ── 5. plays ─────────────────────────────────────────────────────────────────

create table if not exists public.plays (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  fingerprint text not null,
  title text,
  artist text,
  album text,
  source text,
  device_id text,
  started_at timestamptz not null,
  listened_ms int not null default 0,
  completed boolean not null default false,
  unique (user_id, fingerprint, started_at)
);

-- ── 6. track_stats_daily ─────────────────────────────────────────────────────

create table if not exists public.track_stats_daily (
  user_id uuid not null references public.profiles (id) on delete cascade,
  day date not null,
  fingerprint text not null,
  play_count int not null default 0,
  listened_ms bigint not null default 0,
  primary key (user_id, day, fingerprint)
);

-- ── 7. artist_follows ────────────────────────────────────────────────────────

create table if not exists public.artist_follows (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  artist_name text not null,
  mbid text,
  followed_at timestamptz not null default now(),
  unique (user_id, artist_name)
);

-- ── 8. sync_state ────────────────────────────────────────────────────────────

create table if not exists public.sync_state (
  user_id uuid not null references public.profiles (id) on delete cascade,
  device_id text not null,
  last_pulled_at timestamptz,
  last_pushed_at timestamptz,
  primary key (user_id, device_id)
);

-- ── 9. telegram_links ────────────────────────────────────────────────────────
-- Maps a Telegram account to exactly one profile. Written only by the
-- telegram-auth edge function (service role, bypasses RLS); users may read
-- their own row through RLS.

create table if not exists public.telegram_links (
  telegram_id bigint primary key,
  user_id uuid not null references public.profiles (id) on delete cascade
);

-- ── 10. telegram_sessions ────────────────────────────────────────────────────
-- One-time sign-in handoff rows. Reconciled flow (see supabase/functions/
-- telegram-auth/index.ts): the edge function stores {email, token_hash} next
-- to the app-generated token; the client redeems via
-- redeem_telegram_session() and finishes with auth.verifyOTP(tokenHash).
-- `jwt` is reserved for the Stage 2.2 remote-control session handoff and is
-- therefore NULLABLE (the Stage 1.2 flow never stores a JWT here).
-- No RLS policies: reachable ONLY through redeem_telegram_session() (security
-- definer) or the service role — anon/authenticated get no grants at all.

create table if not exists public.telegram_sessions (
  token text primary key,
  user_id uuid references public.profiles (id) on delete cascade,
  email text,
  token_hash text,
  jwt text,
  refresh_token text,
  expires_at timestamptz,
  used boolean not null default false,
  created_at timestamptz not null default now()
);

-- ── 11. New-auth-user trigger ────────────────────────────────────────────────

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      split_part(coalesce(new.email, 'listener'), '@', 1)
    )
  )
  on conflict (id) do nothing;

  insert into public.user_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── 12. One-time Telegram session redeem ─────────────────────────────────────
-- Atomic claim: marks the session used and returns the magic-link payload in
-- the same statement, so a token can never be redeemed twice. Exposed to
-- anon/authenticated because the CLIENT polls this rpc while the Telegram
-- sign-in is pending. `refresh_token` is always null in the Stage 1.2 flow —
-- kept in the signature for the Stage 2.2 remote-control handoff.
--
-- Naming note: the plpgsql parameter `token` collides with the column name,
-- so the WHERE clause qualifies it as `redeem_telegram_session.token` and the
-- table columns are aliased (`ts.`) to dodge the RETURNS TABLE out-params.

create or replace function public.redeem_telegram_session(token text)
returns table (email text, token_hash text, refresh_token text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  update public.telegram_sessions as ts
     set used = true
   where ts.token = redeem_telegram_session.token
     and ts.used = false
     and ts.expires_at is not null
     and ts.expires_at > now()
  returning ts.email, ts.token_hash, ts.refresh_token;
end;
$$;

revoke all on function public.redeem_telegram_session(text) from public;
grant execute on function public.redeem_telegram_session(text)
  to anon, authenticated;

-- ── 13. RLS + grants ─────────────────────────────────────────────────────────
-- Owner-only access everywhere: `user_id = auth.uid()` (profiles keys on
-- `id = auth.uid()`). Every table has RLS enabled; telegram_sessions is the
-- deliberate exception with NO policy (service-role / definer only).

alter table public.profiles enable row level security;
alter table public.devices enable row level security;
alter table public.user_settings enable row level security;
alter table public.plays enable row level security;
alter table public.track_stats_daily enable row level security;
alter table public.artist_follows enable row level security;
alter table public.sync_state enable row level security;
alter table public.telegram_links enable row level security;
alter table public.telegram_sessions enable row level security;

drop policy if exists "profiles_owner_all" on public.profiles;
create policy "profiles_owner_all" on public.profiles
  for all
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "devices_owner_all" on public.devices;
create policy "devices_owner_all" on public.devices
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "user_settings_owner_all" on public.user_settings;
create policy "user_settings_owner_all" on public.user_settings
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "plays_owner_all" on public.plays;
create policy "plays_owner_all" on public.plays
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "track_stats_daily_owner_all" on public.track_stats_daily;
create policy "track_stats_daily_owner_all" on public.track_stats_daily
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "artist_follows_owner_all" on public.artist_follows;
create policy "artist_follows_owner_all" on public.artist_follows
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "sync_state_owner_all" on public.sync_state;
create policy "sync_state_owner_all" on public.sync_state
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "telegram_links_owner_all" on public.telegram_links;
create policy "telegram_links_owner_all" on public.telegram_links
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- telegram_sessions: intentionally NO policy. The Supabase default
-- privileges would still grant DML to anon/authenticated — revoke them so
-- the table is reachable exclusively via redeem_telegram_session() and the
-- service role.
revoke all on public.telegram_sessions from anon, authenticated;

grant select, insert, update, delete on
  public.profiles,
  public.devices,
  public.user_settings,
  public.plays,
  public.track_stats_daily,
  public.artist_follows,
  public.sync_state,
  public.telegram_links
  to authenticated;

-- ── 14. Indexes ──────────────────────────────────────────────────────────────

create index if not exists plays_user_started_at_idx
  on public.plays (user_id, started_at desc);

create index if not exists plays_user_fingerprint_idx
  on public.plays (user_id, fingerprint);
