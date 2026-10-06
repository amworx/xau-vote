-- 0017_spread_gate_privileges.sql
--
-- Completes and corrects 0016. Read this before trusting the spread gate.
--
-- WHY A SECOND FILE
--
-- The spread-display gate was applied to the live database as three separate
-- migrations (`spread_display_gate` x2, then `spread_gate_runs_as_owner`) because
-- the first attempt had two defects that only showed up under test. Applied
-- migrations are immutable, so the correct response is a new file that states the
-- final state, not an edit to 0016. 0017 is therefore the authoritative
-- description of how these privileges must look.
--
-- DEFECT 1 - column revoke alone did not remove write access
--
-- 0016 did `REVOKE SELECT (bid, ask)`. That successfully hid the ladder, and a
-- read of bid/ask now fails with 42501. But it never touched INSERT/UPDATE/
-- DELETE, and those were still granted to `anon`.
--
-- This was verified, not assumed. A publishable key is shipped inside the app
-- bundle, so it is public. With it, anyone could:
--   * INSERT a row with an invented bid/ask, thereby controlling `spread_gate`;
--   * UPDATE or DELETE genuine snapshots, including the real OANDA ladder.
--
-- That is worse than the original display breach. The gate would have reported
-- "measured and within limits" on the strength of a number an attacker invented,
-- and the engine's spread veto would have consumed it as genuine. A licence
-- control that can be fed forged inputs is not a control.
--
-- The earlier note claiming "synthetic insert blocked (400)" was wrong. That 400
-- was a JSON parse failure from a malformed test body, not a permission denial.
-- Re-tested with valid JSON, the insert SUCCEEDED. This file closes that hole.
--
-- DEFECT 2 - a security_invoker view cannot read columns the invoker lacks
--
-- With `security_invoker = true`, `spread_gate` evaluated its WHERE clause
-- `bid is not null AND ask is not null` as `anon`, which no longer has those
-- columns. The view therefore could not work. It now runs with owner security
-- (`security_invoker = false`, the default) so the predicate is evaluated as the
-- owner while the view still exposes only a status and an age.
--
-- WHAT THIS LEAVES IN PLACE
--
--   market_snapshots  SELECT on (id, symbol, price, timestamp, source) only
--   spread_gate       SELECT, and it carries no price
--   everything else   no client access at all
--
-- The publishable key therefore cannot read the ladder, cannot write anything,
-- and cannot influence whether the gate reports AVAILABLE.

-- ---------------------------------------------------------------------------
-- 1. market_snapshots: no client writes, no client reads of the ladder.
-- ---------------------------------------------------------------------------

-- Revoke at table level first. This is the step 0016 omitted.
revoke all on table public.market_snapshots from anon, authenticated;

-- Then re-open only the columns the app genuinely needs to render a price.
grant select (id, symbol, price, timestamp, source)
  on table public.market_snapshots to anon, authenticated;

-- Writers are server-side only: the `tick` and `oanda-quote` functions.
grant insert, update, delete on table public.market_snapshots to service_role;

-- ---------------------------------------------------------------------------
-- 2. spread_gate: owner security, no price.
-- ---------------------------------------------------------------------------

create or replace view public.spread_gate as
select
  case
    when count(*) = 0 then 'UNAVAILABLE'
    when max(timestamp) < now() - interval '5 minutes' then 'UNAVAILABLE'
    else 'AVAILABLE_FOR_INTERNAL_USE'
  end                                   as status,
  extract(epoch from (now() - max(timestamp)))::int as age_seconds,
  max(timestamp)                        as measured_at
from public.market_snapshots
where bid is not null and ask is not null;

comment on view public.spread_gate is
  'Boolean spread acceptability, carrying no price. Runs with owner security '
  'because the invoker no longer holds SELECT on the underlying ladder. '
  'Internal-use-only rates (D-20261006-013) are unreachable from client roles.';

revoke all on table public.spread_gate from anon, authenticated;
grant select on public.spread_gate to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Derived tables that also held the ladder.
-- ---------------------------------------------------------------------------
--
-- Revoking market_snapshots does not retract a copy that was already written
-- elsewhere, and these tables carry their own spread_bid/spread_ask/spread_value
-- columns. `analysis_scans` additionally granted anon full INSERT/UPDATE/DELETE/
-- TRUNCATE, so a forged scan row was writable as well as readable.
--
-- Nothing in the app or in any Edge Function reads these four tables (verified by
-- search across src/app/lib and supabase/functions), and all are currently empty
-- except the spread aggregates. So revoking costs nothing functionally and closes
-- both the second read path for the ladder and a second write-forgery path.
--
-- The columns are intentionally NOT dropped: the internal analysis pipeline is
-- still entitled to record what it measured for its own audit trail, and dropping
-- them would destroy that record. Access control is the correct lever here.

revoke all on table public.analysis_scans        from anon, authenticated;
revoke all on table public.latest_analysis       from anon, authenticated;
revoke all on table public.spread_status         from anon, authenticated;
revoke all on table public.outcome_recorder_summary from anon, authenticated;

grant all on table public.analysis_scans        to service_role;
grant all on table public.latest_analysis       to service_role;
grant select on table public.spread_status      to service_role;
grant select on table public.outcome_recorder_summary to service_role;