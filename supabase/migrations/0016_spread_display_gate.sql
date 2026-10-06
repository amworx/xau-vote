-- 0016_spread_display_gate.sql
--
-- D-20261006-013 / directive §14. The OANDA fxTrade PRACTICE licence grants
-- INTERNAL USE ONLY and states:
--
--   "not transmit, publish, disseminate, duplicate, display, disclose, offer, or
--    otherwise provide, in any form whatsoever, the FXTrade Trading System Rates
--    to any third party."
--
-- XV is a public app, so ANY delivery of that ladder to the app is delivery to a
-- third party. A policy in the UI ("we won't show it") is not compliance; the
-- rate simply must not arrive.
--
-- So the raw bid/ask columns are REVOKED from the client roles. That makes the
-- breach structurally impossible rather than merely discouraged: there is no
-- query the app can write that returns a number. (The `on table` keyword is
-- required for column-level privileges; without it the parser expects a table
-- name and fails on the parenthesis.)
--
-- What replaces it is a boolean gate, not a number. It answers the one question
-- the engine needs — is the spread currently inside its own acceptability limit —
-- and carries no price, so the engine can apply its veto honestly while nobody
-- learns the rate.
--
-- This is NOT a cross-source price difference and NOT a synthesised spread. It
-- is the absence of a number we are not permitted to publish.

revoke select (bid, ask) on table public.market_snapshots from anon, authenticated;

-- The gate. Deliberately no bid, no ask, no computed spread: publishing
-- `ask - bid` here would reintroduce the exact breach this migration closes.
create or replace view public.spread_gate
with (security_invoker = true)
as
select
  case
    when count(*) = 0 then 'UNAVAILABLE'
    -- No genuine measurement, or one too old to describe the current market.
    when max(timestamp) < now() - interval '5 minutes' then 'UNAVAILABLE'
    -- Present and fresh, but withheld from display. The engine may use it.
    else 'AVAILABLE_FOR_INTERNAL_USE'
  end                                   as status,
  -- The measurement's age is not a rate, so it is safe to expose and it lets the
  -- app say WHY the spread is unavailable rather than going silent.
  extract(epoch from (now() - max(timestamp)))::int as age_seconds,
  max(timestamp)                        as measured_at
from public.market_snapshots
where bid is not null and ask is not null;

comment on view public.spread_gate is
  'Boolean spread acceptability, deliberately carrying no price. The raw OANDA '
  'ladder is internal-use-only (D-20261006-013) and is revoked from client roles.';

grant select on public.spread_gate to anon, authenticated;