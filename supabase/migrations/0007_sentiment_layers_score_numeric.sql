-- §5.2 does not score policy as an integer: it defines
--   policy_score_effective = raw_score * exp(-days_since_event / 30)
-- which is fractional by construction (a 19-day-old hike reads -1.06). The
-- column was smallint, so the first real policy write failed outright with
-- 'invalid input syntax for type smallint'. Widening to numeric(4,2) lets the
-- column hold the decayed score that actually drives the verdict; the undamped
-- §5.2 number stays in detail.raw_score.
--
-- The CHECK is kept and still binds: -2 <= effective <= 2 for every layer.
alter table sentiment_layers
  alter column score type numeric(4,2) using score::numeric;

comment on column sentiment_layers.score is
  'Effective layer score as the engine consumes it. Integer for positioning; fractional for policy, which §5.2 decays by exp(-days/30). The undamped §5.2 number is in detail.raw_score.';