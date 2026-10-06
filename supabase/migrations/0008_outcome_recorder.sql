-- 0008_outcome_recorder.sql
--
-- Outcome recorder: the measurement layer the analysis engine never had.
--
-- Protocol and rationale: docs/outcome-recorder-protocol.md (pre-registered,
-- frozen 2026-10-06, BEFORE any row was written).
--
-- Two properties this migration is built around:
--
--  1. The levels the product withholds from users are stored HERE. That is what
--     makes it possible to withhold prices from the UI while still being
--     accountable for every verdict. The table is service-role only, so the app
--     can neither read the levels nor forge an outcome.
--
--  2. NO_TRADE decisions are recorded too, alongside a pre-registered forced-trade
--     counterfactual. Without this, abstentions are unfalsifiable and the record
--     is a highlight reel.
--
-- Never edit an applied migration. This file is new; do not amend it after deploy.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------
create table if not exists public.scan_decisions (
  id                    uuid primary key default gen_random_uuid(),

  -- Idempotency key from the client. A retry of the same scan is a no-op, which
  -- matters because the app scans every 60s and mobile networks retry.
  decision_key          text not null unique,

  -- ---- What the engine decided ------------------------------------------
  verdict               text   not null
    check (verdict in ('LONG','SHORT','NO_TRADE')),
  -- LONG/SHORT for live trades; FORCED_LONG/FORCED_SHORT only when
  -- is_counterfactual is true.
  side                  text   not null
    check (side in ('LONG','SHORT','FORCED_LONG','FORCED_SHORT')),
  grade                 text   not null
    check (grade in ('A_PLUS','A','B','INSUFFICIENT')),
  technical_score       int    not null,
  final_score           double precision not null,

  reason_codes          text[] not null default '{}',
  vetoes                text[] not null default '{}',
  data_quality          text[] not null default '{}',

  -- ---- Context layers, stored so confounding can be measured later -------
  macro_alignment       int    check (macro_alignment in (-1,0,1)),
  macro_agrees          int    check (macro_agrees    in (-1,0,1)),
  sentiment_alignment   int    check (sentiment_alignment in (-1,0,1)),
  sentiment_agrees      int    check (sentiment_agrees    in (-1,0,1)),
  conflict_penalty      int    not null default 0,

  -- ---- Levels: STORED, NEVER PUBLISHED -----------------------------------
  entry                 double precision,
  stop_loss             double precision,
  tp1                   double precision,
  tp2                   double precision,
  tp3                   double precision,
  risk_distance         double precision,
  risk_distance_atr     double precision,
  atr5m                 double precision,

  spread_status         text   not null,
  spread_value          double precision,

  -- ---- Timing -----------------------------------------------------------
  -- decided_at is the close time of the last CLOSED m15 bar, NOT the moment the
  -- request was made. A late report is a data-quality signal, not a rounding
  -- detail, which is why run_at is kept separately.
  decided_at            timestamptz not null,
  run_at                timestamptz not null default now(),
  -- 12 closed m15 bars == 3 hours, per protocol section 3.
  resolve_at            timestamptz not null
                        default (decided_at + interval '3 hours'),

  -- ---- Fingerprint ------------------------------------------------------
  -- Computed server-side from thresholds compiled into the Edge Function. The
  -- client also computes one; a disagreement voids the row rather than trusting
  -- either party. A code deploy that changes a threshold starts a new cohort
  -- instead of silently rewriting history.
  engine_version        text   not null,
  rule_hash             text   not null,
  void_reason           text,

  -- ---- Clustering -------------------------------------------------------
  -- Overlapping setups in one gold move are ONE observation. Protocol s3.
  cluster_id            uuid,
  is_repeat             boolean not null default false,

  is_counterfactual     boolean not null default false,

  -- ---- Settlement -------------------------------------------------------
  status                text   not null default 'PENDING'
    check (status in ('PENDING','RESOLVED','VOID')),
  outcome               text
    check (outcome in ('TP1','TP2','TP3','STOP','TIMEOUT','VOID')),
  -- Primary metric. r_gross is kept for diagnosis; r_net is what is reported.
  r_gross               double precision,
  r_net                 double precision,
  spread_cost_r         double precision,
  exit_price            double precision,
  bars_used             int,
  settled_at            timestamptz,

  created_at            timestamptz not null default now(),

  constraint scan_decisions_levels_present check (
    is_counterfactual
    or verdict = 'NO_TRADE'
    or (entry is not null and stop_loss is not null and tp1 is not null
        and risk_distance is not null and risk_distance > 0)
  ),
  constraint scan_decisions_resolved_has_outcome check (
    status <> 'RESOLVED' or (outcome is not null and r_net is not null)
  )
);

comment on table public.scan_decisions is
  'Forward outcome record. Levels are stored here and never published; the app '
  'cannot read them. Protocol: docs/outcome-recorder-protocol.md.';

-- Settlement sweeps PENDING rows in time order.
create index if not exists scan_decisions_pending_idx
  on public.scan_decisions (resolve_at)
  where status = 'PENDING';

-- The headline metric: resolved, non-repeat, non-counterfactual rows only.
create index if not exists scan_decisions_metric_idx
  on public.scan_decisions (rule_hash, decided_at)
  where status = 'RESOLVED' and is_repeat = false and not is_counterfactual;

create index if not exists scan_decisions_cluster_idx
  on public.scan_decisions (cluster_id);

-- ---------------------------------------------------------------------------
-- Cluster assignment
--
-- A new decision for the same side within the horizon is a repeat of the open
-- episode and inherits that episode's id. Implemented as a trigger so the rule
-- lives with the data rather than in each caller.
-- ---------------------------------------------------------------------------
create or replace function public.scan_decisions_assign_cluster()
returns trigger
language plpgsql
as $$
declare
  open_episode public.scan_decisions;
begin
  if new.status = 'VOID' then
    new.cluster_id := new.id;
    return new;
  end if;

  select d.* into open_episode
  from public.scan_decisions d
  where d.side = new.side
    and d.status = 'PENDING'
    and d.decided_at > new.decided_at - interval '3 hours'
    and d.decided_at <= new.decided_at
    and d.is_repeat = false
  order by d.decided_at asc
  limit 1;

  if found then
    new.cluster_id  := open_episode.id;
    new.is_repeat   := true;
  else
    new.cluster_id  := new.id;
    new.is_repeat   := false;
  end if;

  return new;
end;
$$;

drop trigger if exists scan_decisions_cluster_trg on public.scan_decisions;
create trigger scan_decisions_cluster_trg
  before insert on public.scan_decisions
  for each row execute function public.scan_decisions_assign_cluster();

-- ---------------------------------------------------------------------------
-- Access: service role ONLY.
--
-- No anon or authenticated policies, deliberately. The app must not be able to
-- insert a decision (it could forge a verdict) or read the withheld levels (it
-- would defeat the product's central promise). Any future outcome UI goes
-- through a function returning aggregates, never raw rows.
-- ---------------------------------------------------------------------------
alter table public.scan_decisions enable row level security;

revoke all on public.scan_decisions from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Headline view: kill criteria in one query.
--
-- Live vs counterfactual is computed side by side over the SAME cohort and
-- window, because criterion 2 only means anything as a paired comparison.
-- ---------------------------------------------------------------------------
create or replace view public.outcome_recorder_summary
with (security_invoker = true)
as
select
  d.rule_hash,
  min(d.engine_version)                       as engine_version,
  date_trunc('day', d.decided_at)             as day,

  count(*) filter (
    where not d.is_repeat and not d.is_counterfactual
  )                                           as live_trades,
  avg(d.r_net) filter (
    where not d.is_repeat and not d.is_counterfactual
  )                                           as live_mean_r_net,
  avg(d.r_gross) filter (
    where not d.is_repeat and not d.is_counterfactual
  )                                          as live_mean_r_gross,
  avg(d.spread_cost_r) filter (
    where not d.is_repeat and not d.is_counterfactual
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
    where not d.is_repeat and not d.is_counterfactual
  )                                           as forced_advantage_r,

  count(*) filter (where d.void_reason is not null) as voided
from public.scan_decisions d
where d.status = 'RESOLVED'
group by d.rule_hash, date_trunc('day', d.decided_at);

comment on view public.outcome_recorder_summary is
  'Kill criteria 1, 2 and 3 in one query. Protocol: docs/outcome-recorder-protocol.md.';

-- No anon/authenticated grants on the view either; it inherits the table's
-- emptiness under security_invoker.
revoke all on public.outcome_recorder_summary from anon, authenticated;