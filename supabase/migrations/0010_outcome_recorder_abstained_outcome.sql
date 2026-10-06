-- 0010_outcome_recorder_abstained_outcome.sql
--
-- Found by running settle against a real abstention rather than only against
-- trades.
--
-- A NO_TRADE row has no levels, so resolveOne returned null for it and the row
-- stayed PENDING. Every subsequent settle run re-fetched and re-examined those
-- rows forever. That is the worst kind of bug for a measurement layer: it looks
-- like "no data yet", it never errors, and it quietly costs a full table scan
-- every run.
--
-- Fix: an abstention closes at its horizon as ABSTAINED with a zero-R result.
-- The row is counted, not scored. The summary view reports the abstention count
-- separately and excludes ABSTAINED from the trade metric, because expectancy
-- per TRADE and the share of decisions the engine declines are different
-- questions and must not be mixed into one number.
--
-- The view is dropped and recreated rather than CREATE OR REPLACE'd because the
-- new column has to be appended, and CREATE OR REPLACE cannot reorder or insert
-- columns in an existing view.
--
-- Never edit an applied migration. This file is new; do not amend it after deploy.

alter table public.scan_decisions
  drop constraint if exists scan_decisions_outcome_check;

alter table public.scan_decisions
  add constraint scan_decisions_outcome_check
    check (outcome in ('TP1','TP2','TP3','STOP','TIMEOUT','ABSTAINED','VOID'));

drop view if exists public.outcome_recorder_summary;

create view public.outcome_recorder_summary
with (security_invoker = true)
as
select
  d.rule_hash,
  min(d.engine_version)                       as engine_version,
  date_trunc('day', d.decided_at)             as day,

  count(*) filter (
    where not d.is_repeat and not d.is_counterfactual and d.outcome <> 'ABSTAINED'
  )                                           as live_trades,
  avg(d.r_net) filter (
    where not d.is_repeat and not d.is_counterfactual and d.outcome <> 'ABSTAINED'
  )                                           as live_mean_r_net,
  avg(d.r_gross) filter (
    where not d.is_repeat and not d.is_counterfactual and d.outcome <> 'ABSTAINED'
  )                                          as live_mean_r_gross,
  avg(d.spread_cost_r) filter (
    where not d.is_repeat and not d.is_counterfactual and d.outcome <> 'ABSTAINED'
  )                                          as mean_spread_cost_r,
  count(*) filter (
    where d.outcome = 'STOP'
  )                                           as stops,
  count(*) filter (
    where d.outcome = 'TIMEOUT'
  )                                           as timeouts,

  count(*) filter (
    where d.is_counterfactual and not d.is_repeat
  )                                           as forced_trades,
  avg(d.r_net) filter (
    where d.is_counterfactual and not d.is_repeat
  )                                           as forced_mean_r_net,

  -- Criterion 2. Positive means the forced counterfactual beat the live engine,
  -- which is a failure of the filters, not a win.
  avg(d.r_net) filter (
    where d.is_counterfactual and not d.is_repeat
  ) - avg(d.r_net) filter (
    where not d.is_repeat and not d.is_counterfactual and d.outcome <> 'ABSTAINED'
  )                                           as forced_advantage_r,

  count(*) filter (where d.void_reason is not null) as voided,

  -- Abstentions are counted, never scored. Seeing this grow toward most
  -- decisions is the honest signal that the engine is mostly saying no.
  count(*) filter (
    where not d.is_repeat and d.outcome = 'ABSTAINED'
  )                                           as abstentions

from public.scan_decisions d
where d.status = 'RESOLVED'
group by d.rule_hash, date_trunc('day', d.decided_at);

comment on view public.outcome_recorder_summary is
  'Kill criteria 1, 2 and 3 in one query. Abstentions are counted separately and '
  'excluded from the trade metric. Protocol: docs/outcome-recorder-protocol.md.';

revoke all on public.outcome_recorder_summary from anon, authenticated;