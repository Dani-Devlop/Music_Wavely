-- Stage 3 audit (SEC-8): the sync backend pushes rows WITHOUT an explicit
-- user_id, relying on PostgREST/server defaults of auth.uid() (see the
-- contract documented in lib/data/sync/supabase_sync_backend.dart). The
-- columns were `not null` with no default, so every such push failed the
-- NOT NULL constraint. These defaults make the documented contract real.
-- RLS policies (0001_init.sql) still scope every table to auth.uid(), so
-- a client can never write into another user's rows.

alter table public.devices
  alter column user_id set default auth.uid();

alter table public.user_settings
  alter column user_id set default auth.uid();

alter table public.plays
  alter column user_id set default auth.uid();

alter table public.track_stats_daily
  alter column user_id set default auth.uid();

alter table public.artist_follows
  alter column user_id set default auth.uid();

alter table public.sync_state
  alter column user_id set default auth.uid();

alter table public.telegram_links
  alter column user_id set default auth.uid();
