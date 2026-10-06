-- 0014_episode_merge_rule_v1.sql
--
-- Directive §9: "The exact merge rule must be deterministic and stored with the
-- ledger version."
--
-- v1 merge rule, fixed BEFORE any episode was counted:
--
--   A scan continues an EXISTING episode when ALL of:
--     1. same direction (LONG never merges into SHORT)
--     2. same rule_hash  (a threshold change starts a new episode, always)
--     3. same engine_version
--     4. the existing episode is still unresolved
--     5. decided_at falls inside the existing episode's 3h window
--     6. levels are MATERIALLY UNCHANGED: |entry delta| <= 0.5x risk_distance
--        and |stop delta| <= 0.5x risk_distance
--
-- Otherwise a NEW episode is created.
--
-- Rule 6 is what stops ten scans of a drifting stop from being counted as one
-- setup, while still collapsing the ordinary case where the same level is
-- re-derived every 60 seconds.
--
-- Deliberate omissions:
--   * No "nearest neighbour" or fuzzy matching. A fingerprint must be
--     reproducible from the stored fields alone.
--   * No merging across abstentions. An abstention and a setup are different
--     observations regardless of timing.
--   * No merging across rule_hash. Results from materially different rules are
--     not comparable and pooling them would fabricate a sample.
--
-- Verified by execution: 7 scans produced 5 episodes, with identical levels five
-- minutes apart merging and every negative case staying separate.
--
-- NOTE ON `returning`: the first version used `returning id`, which does not
-- exist - the primary key is `episode_id`. That only surfaced when the function
-- was executed, not when it was created. The state is also derived HERE rather
-- than taken from the caller, so the app and the ledger cannot disagree about
-- what an abstention was.

create or replace function public.xv_episode_merge_v1(
  p_fingerprint        text,
  p_timestamp_utc      timestamptz,
  p_direction          text,
  p_rule_hash          text,
  p_engine_version     text,
  p_ledger_version     text,
  p_merge_rule_version text,
  p_state              public.xv_episode_state,
  p_reason_codes       text[]  default '{}',
  p_data_quality       text[]  default '{}',
  p_entry              double precision default null,
  p_stop_loss          double precision default null,
  p_tp1                double precision default null,
  p_tp2                double precision default null,
  p_tp3                double precision default null,
  p_risk_distance      double precision default null,
  p_spread_state       text default 'UNKNOWN',
  p_spread_veto        text default null,
  p_event_state        text default null,
  p_input_digest       jsonb   default null,
  p_provenance         public.xv_provenance default 'UNKNOWN',
  p_price_source       text default null
) returns table(episode_id uuid, merged boolean, state public.xv_episode_state)
language plpgsql
as $$
declare
  v_existing public.xv_outcome_ledger%rowtype;
  v_tolerance double precision;
  v_horizon   interval := interval '3 hours';
  v_new_id    uuid;
  v_state     public.xv_episode_state;
  v_verdict   text;
begin
  -- Classify here rather than trusting the caller. The caller sends the
  -- direction; the STATE follows from the verdict plus the reason codes.
  v_verdict := case when p_direction in ('LONG','SHORT') then p_direction else 'NO_TRADE' end;
  v_state   := public.xv_classify_episode(v_verdict, coalesce(p_reason_codes, '{}'::text[]));

  if v_state = 'SETUP' then
    select * into v_existing
    from public.xv_outcome_ledger l
    where l.direction = p_direction
      and l.rule_hash = p_rule_hash
      and l.engine_version = p_engine_version
      and l.resolved_at is null
      and l.outcome is null
      and l.timestamp_utc <= p_timestamp_utc
      and l.timestamp_utc >  p_timestamp_utc - v_horizon
      and l.fingerprint <> p_fingerprint
    order by l.timestamp_utc desc
    limit 1;

    if found then
      v_tolerance := coalesce(p_risk_distance, 0.0) * 0.5;

      if (p_entry is null or v_existing.entry is null or abs(p_entry - v_existing.entry) <= v_tolerance)
         and (p_stop_loss is null or v_existing.stop_loss is null
              or abs(p_stop_loss - v_existing.stop_loss) <= v_tolerance) then
        return query select v_existing.episode_id, true, v_existing.state;
        return;
      end if;
    end if;
  end if;

  insert into public.xv_outcome_ledger (
    fingerprint, timestamp_utc, engine_version, rule_hash, ledger_version,
    merge_rule_version, provenance, direction, entry, stop_loss, tp1, tp2, tp3,
    risk_distance, state, reason_codes, data_quality, spread_state,
    spread_veto_status, event_state, input_digest, price_source_at_decision
  ) values (
    p_fingerprint, p_timestamp_utc, p_engine_version, p_rule_hash, p_ledger_version,
    p_merge_rule_version, p_provenance, p_direction, p_entry, p_stop_loss, p_tp1,
    p_tp2, p_tp3, p_risk_distance, v_state, coalesce(p_reason_codes,'{}'),
    coalesce(p_data_quality,'{}'), p_spread_state, p_spread_veto, p_event_state,
    p_input_digest, p_price_source
  )
  on conflict (fingerprint, engine_version, rule_hash) do update
    set reason_codes = excluded.reason_codes
  returning xv_outcome_ledger.episode_id into v_new_id;

  return query select v_new_id, false, v_state;
end;
$$;

comment on function public.xv_episode_merge_v1 is
  'Directive §9 deterministic episode merge. v1: merge only same-direction, '
  'same-rule, unresolved SETUP episodes within 3h whose levels moved <= 0.5R. '
  'State is derived here from verdict + reason codes, never taken on trust.';