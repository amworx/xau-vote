-- 0022_goldhunts_session_view.sql
--
-- Gold Hunts as EXTERNAL SESSION VIEW (directive §2, D-20261006-016).
-- Session context and benchmark only. Never votes, never confirmation.
--
-- WHAT IS STORED, AND WHY IN TWO PLACES
--
-- `goldhunts_snapshots` archives the RAW provider payload on every sync. This
-- is the §3 reconciliation evidence base: independent tallies and XV-bar
-- reconstructions are computed from archived snapshots, never from memory and
-- never from the provider's own outcome labels. Append-only; pruned past 72h
-- by the sync function (sessions close daily, so 72h covers every open call's
-- full window plus its scoring).
--
-- `goldhunts_calls` holds one row per provider call id, upserted. It carries
-- LABELS ONLY - direction verbatim, session, timestamps, status. There are
-- deliberately NO entry/stop/target/headline columns: headlines embed levels
-- ("ranging inside 4299.95 to 4328.48"), so even the headline may not reach the
-- app. The directive forbids supplying XV Entry/SL/TP from provider levels, and
-- the strongest enforcement is a column that does not exist.
--
-- `goldhunts_session_view` is the ONLY client-readable surface. Owner-security
-- view (same pattern as spread_gate: a security_invoker view could not read
-- columns the invoker lacks), exposing label/session/timestamps/status and
-- nothing else. The app computes STALE itself: provider stale flag OR
-- now - data_as_of > 6 hours (directive §2 freshness rule).
--
-- WHAT NEVER HAPPENS HERE
--
-- These tables are not trade_ideas, are not read by build-consensus, and
-- cannot enter the 15M vote pool by construction. A session call is not a 15M
-- setup (product rule 1), and one publisher is not confirmation (directive §6).
--
-- Sync: `goldhunts-sync` hourly at :45 (provider regenerates hourly). Uses the
-- LIVE endpoint only:
--   https://ebhodyknnbdhdiezrtsk.supabase.co/functions/v1/refresh-gold-data?dataset=gold-signals
-- The static gold-signals.json file was 11 days stale on the day of review and
-- must never be used. On fetch failure the function fails loudly and writes
-- nothing; the previous rows age into STALE by the 6-hour rule rather than
-- being replaced by stale data presented as fresh.

create table if not exists public.goldhunts_snapshots (
  id            uuid primary key default gen_random_uuid(),
  fetched_at    timestamptz not null default now(),
  data_as_of    timestamptz,
  provider_stale boolean not null default false,
  signal_count  integer not null default 0,
  payload       jsonb not null
);

comment on table public.goldhunts_snapshots is
  'Append-only archive of raw Gold Hunts payloads for §3 outcome '
  'reconciliation. Pruned past 72h by goldhunts-sync. Service-only.';

create table if not exists public.goldhunts_calls (
  provider_id    text primary key,
  direction      text not null,
  session        text not null,
  session_date   date,
  published_at   timestamptz,
  data_as_of     timestamptz,
  provider_stale boolean not null default false,
  status         text not null default 'open',
  fetched_at     timestamptz not null default now()
);

comment on table public.goldhunts_calls is
  'Latest known Gold Hunts session calls, upserted by id. LABELS ONLY - no '
  'entry/stop/target/headline columns exist on purpose, so provider levels can '
  'never leak into XV. Service-only; clients read goldhunts_session_view.';

create table if not exists public.goldhunts_feed_state (
  id             boolean primary key default true check (id),
  fetched_at     timestamptz not null default now(),
  data_as_of     timestamptz,
  provider_stale boolean not null default false,
  signal_count   integer not null default 0,
  open_count     integer not null default 0
);

comment on table public.goldhunts_feed_state is
  'Single-row freshness state for the Gold Hunts feed. Service-only.';

alter table public.goldhunts_snapshots enable row level security;
alter table public.goldhunts_calls enable row level security;
alter table public.goldhunts_feed_state enable row level security;

-- No client policies on purpose: anon and authenticated get no access at all.
revoke all on table public.goldhunts_snapshots from anon, authenticated;
revoke all on table public.goldhunts_calls from anon, authenticated;
revoke all on table public.goldhunts_feed_state from anon, authenticated;
grant all on table public.goldhunts_snapshots to service_role;
grant all on table public.goldhunts_calls to service_role;
grant all on table public.goldhunts_feed_state to service_role;

-- The only client-readable surface. Labels, sessions, timestamps, status.
-- No levels, no headlines, no conviction scores: §8 forbids LOW/MEDIUM/HIGH as
-- validation substitutes, and headlines embed prices.
create or replace view public.goldhunts_session_view as
select
  provider_id,
  direction,
  session,
  session_date,
  published_at,
  data_as_of,
  provider_stale,
  status,
  fetched_at
from public.goldhunts_calls
where status = 'open';

comment on view public.goldhunts_session_view is
  'Open Gold Hunts session calls, labels only. EXTERNAL SESSION VIEW '
  '(D-20261006-016): never votes, never confirmation. The app marks STALE '
  'when provider_stale or now - data_as_of > 6 hours. Attribution to '
  'https://goldhunts.com required wherever shown.';

revoke all on table public.goldhunts_session_view from anon, authenticated;
grant select on public.goldhunts_session_view to anon, authenticated;

-- Hourly sync, off the provider's regeneration point (calls publish ~:35).
do $$
declare existing bigint;
begin
  select jobid into existing
    from cron.job
   where jobname = 'xv-goldhunts-sync';

  if existing is not null then
    perform cron.unschedule(existing);
  end if;

  perform cron.schedule(
    'xv-goldhunts-sync',
    '45 * * * *',
    $cron$ select public.xv_invoke_function('goldhunts-sync'); $cron$
  );
end;
$$;