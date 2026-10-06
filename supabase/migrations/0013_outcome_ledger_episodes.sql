-- 0013_outcome_ledger_episodes.sql
--
-- Directive §9 and §10. The existing `scan_decisions` table records every SCAN.
-- The evaluation unit must be the INDEPENDENT_SETUP_EPISODE, because scans run
-- every 60 seconds and ten scans inside one gold move are one observation, not
-- ten. The existing `is_repeat` flag already clusters those; this migration
-- formalises the unit, versions the merge rule, and records every episode STATE
-- so an abstention is a countable observation rather than a gap in the
-- denominator.
--
-- Nothing here restarts the recorder. Forward recording is already running; this
-- makes its output evaluable. Per §11 the forward record must never be delayed by
-- later integrations, and it has not been.

-- ---------------------------------------------------------------------------
-- Episode states
--
-- Deliberately a superset of the engine's single `noTrade` verdict. The engine
-- collapses everything non-directional into `noTrade` with a reason code, but
-- "declined because the market was closed" and "declined because we have no
-- measured macro" are different facts and must not share a bucket in the ledger.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'xv_episode_state') then
    create type public.xv_episode_state as enum (
      'SETUP',                -- a directional setup was generated
      'NO_TRADE',             -- nothing qualified, information was sufficient
      'INSUFFICIENT_DATA',    -- required measurement missing or unusable
      'NEWS_LOCK',            -- a high-impact release is inside the blackout
      'VOLATILITY_BLOCK',     -- volatility regime vetoed the setup
      'DATA_QUALITY_BLOCK'    -- feed staleness, gap or degradation blocked it
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Provenance, mandatory.
--
-- Null provenance must not mean "probably fine". DEFAULT is 'UNKNOWN' rather
-- than a null column so that an unqualified write is visibly unqualified.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'xv_provenance') then
    create type public.xv_provenance as enum (
      'INTERNAL',
      'EXTERNAL_PUBLISHER',
      'EXTERNAL_SESSION_VIEW',
      'THIRD_PARTY_MODEL',
      'OFFICIAL_CONTEXT',
      'UNKNOWN'
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- The ledger.
--
-- One row per INDEPENDENT_SETUP_EPISODE. `scan_decisions` keeps the raw scan
-- trail; this table is what gets counted.
-- ---------------------------------------------------------------------------
create table if not exists public.xv_outcome_ledger (
  episode_id        uuid primary key default gen_random_uuid(),

  -- Deterministic identity: repeated scans of one episode collapse onto this.
  -- Hashing the components means a replay of the same inputs produces the same
  -- id, so the ledger is reproducible rather than merely idempotent.
  fingerprint       text not null,

  timestamp_utc     timestamptz not null,
  symbol            text not null default 'XAUUSD',
  timeframe         text not null default '15m',

  -- Versioning. Results are never combined across rule versions.
  engine_version    text not null,
  rule_hash         text not null,
  ledger_version    text not null,
  -- Merge rule is versioned alongside the data it produced, so a later change to
  -- how episodes are grouped cannot retroactively alter historical counts.
  merge_rule_version text not null,

  provenance        public.xv_provenance not null default 'UNKNOWN',
  model_owner       text,
  methodology_id    text,
  upstream_dataset_id text,

  direction         text check (direction in ('LONG','SHORT','NONE')),
  entry             double precision,
  stop_loss         double precision,
  tp1               double precision,
  tp2               double precision,
  tp3               double precision,
  risk_distance     double precision,

  state             public.xv_episode_state not null,
  reason_codes      text[] not null default '{}',

  -- Context at decision time.
  data_quality      text[] not null default '{}',
  spread_state      text not null,
  spread_veto_status text,
  event_state       text,
  input_digest      jsonb,

  -- Settlement.
  outcome           text,
  net_outcome       text,
  cost_model        text,   -- 'measured_spread' | 'cost_model_unavailable'
  r_gross           double precision,
  r_net             double precision,
  resolved_at       timestamptz,

  -- Provenance of the settlement inputs, kept separately from the decision's.
  outcome_source    text,
  price_source_at_decision text,
  price_source_at_outcome  text,

  created_at        timestamptz not null default now(),

  unique (fingerprint, engine_version, rule_hash)
);

comment on table public.xv_outcome_ledger is
  'One row per INDEPENDENT_SETUP_EPISODE. Evaluation unit per directive §9. '
  'Merge rule is versioned; results are never combined across rule_hash.';

-- Episode enumeration. The headline metric reads this index.
create index if not exists xv_outcome_ledger_metric_idx
  on public.xv_outcome_ledger (rule_hash, engine_version)
  where state = 'SETUP';

-- Episode fingerprint: one episode per open cluster.
create index if not exists xv_outcome_ledger_fingerprint_idx
  on public.xv_outcome_ledger (fingerprint);

-- ---------------------------------------------------------------------------
-- Classify an engine result into an episode state.
--
-- Pure mapping from the engine's verdict plus reason codes. Lives in SQL so the
-- ledger cannot drift from the classifier the recorder uses.
--
-- Order matters and is not alphabetical: a blackout is checked before the generic
-- no-trade, because a release inside the window is a more specific and more
-- actionable fact than "nothing qualified".
-- ---------------------------------------------------------------------------
create or replace function public.xv_classify_episode(
  verdict text,
  reason_codes text[]
) returns public.xv_episode_state
language plpgsql
immutable
as $$
declare
  has text;
begin
  if verdict in ('LONG','SHORT') then
    return 'SETUP';
  end if;

  -- veto / block reasons, checked in specificity order
  foreach has in array coalesce(reason_codes, '{}'::text[]) loop
    if has = 'v1Blackout' then return 'NEWS_LOCK'; end if;
    if has = 'v4VolatilityExtreme' then return 'VOLATILITY_BLOCK'; end if;
    if has = 'v2SpreadUnevaluated' then return 'DATA_QUALITY_BLOCK'; end if;
  end loop;

  foreach has in array coalesce(reason_codes, '{}'::text[]) loop
    if has = 'v3DataStale' then return 'DATA_QUALITY_BLOCK'; end if;
    if has = 'v8SessionClosed' then return 'DATA_QUALITY_BLOCK'; end if;
  end loop;

  return 'NO_TRADE';
end;
$$;

comment on function public.xv_classify_episode(text, text[]) is
  'Maps an engine verdict plus reason codes onto a ledger episode state.';

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
alter table public.xv_outcome_ledger enable row level security;
revoke all on public.xv_outcome_ledger from anon, authenticated;

-- ---------------------------------------------------------------------------
-- The evaluation view: one row per counted episode.
--
-- Episodes are NOT combined across rule_hash. The pass criterion is evaluated
-- per cohort, because a threshold change mid-record makes a single pooled mean
-- meaningless.
-- ---------------------------------------------------------------------------
create or replace view public.xv_ledger_evaluation
with (security_invoker = true)
as
select
  l.rule_hash,
  l.engine_version,
  l.ledger_version,
  l.merge_rule_version,

  count(*) filter (where l.state = 'SETUP')                       as episodes,
  count(*) filter (where l.state = 'NO_TRADE')                    as no_trade,
  count(*) filter (where l.state = 'INSUFFICIENT_DATA')           as insufficient_data,
  count(*) filter (where l.state = 'NEWS_LOCK')                    as news_lock,
  count(*) filter (where l.state = 'VOLATILITY_BLOCK')            as volatility_block,
  count(*) filter (where l.state = 'DATA_QUALITY_BLOCK')          as data_quality_block,

  -- Primary metric: mean net R over resolved SETUP episodes.
  -- TIMEOUT counts. Dropping unresolved trades is how a losing engine reports a
  -- winning one.
  avg(l.r_net)   filter (where l.state = 'SETUP' and l.r_net is not null) as mean_net_r,
  avg(l.r_gross) filter (where l.state = 'SETUP' and l.r_gross is not null) as mean_gross_r,
  count(*) filter (where l.state = 'SETUP' and l.r_net is not null)       as resolved_setups,
  count(*) filter (where l.state = 'SETUP' and l.net_outcome = 'cost_model_unavailable')
                                                                         as cost_model_unavailable,

  count(*) filter (where l.outcome = 'TP1')   as tp1,
  count(*) filter (where l.outcome = 'STOP')  as stops,
  count(*) filter (where l.outcome = 'TIMEOUT') as timeouts,

  -- Regime coverage. The pre-registered criterion requires at least two.
  count(distinct l.event_state) filter (where l.event_state is not null) as event_states,
  min(l.timestamp_utc) as first_episode,
  max(l.timestamp_utc) as last_episode
from public.xv_outcome_ledger l
group by l.rule_hash, l.engine_version, l.ledger_version, l.merge_rule_version;

comment on view public.xv_ledger_evaluation is
  'Pre-registered evaluation counts, per rule cohort. Directive §10: pass when the '
  '95% lower confidence bound of mean net R > 0 over >=200 episodes across >=2 '
  'volatility regimes; fold when that bound is <= 0.';

revoke all on public.xv_ledger_evaluation from anon, authenticated;