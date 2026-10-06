-- 0018_live_price_cache.sql
--
-- Why the price needs a server-side cache
--
-- The Radar price has to move with the market, but `tick` only runs once a
-- minute (pg_cron has a one-minute floor) and the price provider rate-limits by
-- client IP. Measured on 2026-10-06:
--   * from a workstation, 16 requests at 4s spacing all returned 200;
--   * from the phone, the same cadence returned 429 on every attempt.
--
-- So a client polling upstream directly does not work for real users on shared
-- or mobile networks, which is most of them. That is why this cache exists: the
-- provider is contacted once per window from our own infrastructure, and any
-- number of clients read that one result.
--
-- Why a dedicated table rather than more `market_snapshots` rows
--
-- `market_snapshots` is the evidence base for bars, the outcome ledger and
-- settlement. Writing a live cache row every few seconds would add ~17k rows a
-- day of data that is not evidence - it is a transient display value - and it
-- would make the recorded history harder to reason about. One row, overwritten
-- in place, keeps that table meaning exactly what it means today.
--
-- Access: service_role only. Clients reach the price through the `price-live`
-- Edge Function, not by reading this table, so the cache freshness policy lives
-- in one place instead of being duplicated in every client.

create table if not exists public.live_price_cache (
  id          boolean primary key default true check (id),
  symbol      text        not null default 'XAUUSD',
  price       numeric     not null,
  source      text        not null,
  measured_at timestamptz not null default now()
);

comment on table public.live_price_cache is
  'Single-row cache of the last live XAUUSD price, written by price-live. '
  'Display freshness only - never an evidence source.';

alter table public.live_price_cache enable row level security;

-- No client policies on purpose: anon and authenticated get no access at all.
-- The function uses the service role, which bypasses RLS.

revoke all on table public.live_price_cache from anon, authenticated;
grant all on table public.live_price_cache to service_role;

-- One row, refreshed in place.
insert into public.live_price_cache (id, symbol, price, source)
values (true, 'XAUUSD', 0, 'seed')
on conflict (id) do nothing;

comment on column public.live_price_cache.source is
  'Which provider supplied the number, or "seed" before the first live read.';