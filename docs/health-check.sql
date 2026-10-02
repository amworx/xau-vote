-- XV backend health check. Read-only. See docs/health-check.md.
WITH latest AS (
  SELECT price, timestamp FROM market_snapshots
   ORDER BY timestamp DESC LIMIT 1
),
open_sig AS (
  SELECT count(*) FILTER (
           WHERE status IN ('DEVELOPING','READY','CONFIRMED','ACTIVE','TP1_HIT','TP2_HIT')
         ) AS open_signals,
         count(*) AS total_signals
    FROM consensus_signals
)
SELECT
  (SELECT count(*) FROM trade_ideas)                                AS ideas,
  (SELECT count(DISTINCT trade_idea_id) FROM signal_sources)       AS distinct_ideas,
  (SELECT price FROM latest)                                        AS latest_price,
  round(EXTRACT(EPOCH FROM (now() - (SELECT timestamp FROM latest)))) AS latest_price_age_sec,
  (SELECT open_signals FROM open_sig)                               AS open_signals,
  (SELECT total_signals FROM open_sig)                              AS total_signals,
  (SELECT count(*) FROM cron.job_run_details
    WHERE start_time > now() - interval '24 hours'
      AND status NOT IN ('succeeded'))                             AS failed_jobs_24h,
  (SELECT count(*) FROM cron.job_run_details
    WHERE start_time > now() - interval '10 minutes')               AS runs_last_10m,
  (SELECT round(EXTRACT(EPOCH FROM (now() - max(at))) / 3600)
     FROM ops_heartbeat)                                            AS heartbeat_age_hours;

-- INVARIANT: must never exceed 1. Multiple open signals was a real bug fixed
-- 2026-10-02 (build-consensus stacked a new DEVELOPING row every 5 minutes).
SELECT count(*) FILTER (
         WHERE status IN ('DEVELOPING','READY','CONFIRMED','ACTIVE','TP1_HIT','TP2_HIT')
       ) AS open_signals_should_be_0_or_1
  FROM consensus_signals;