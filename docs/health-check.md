# XV — Backend Health Check

Run this whenever you suspect the pipeline has gone quiet. It is read-only and
safe. Paste into the Supabase SQL editor, or:

```powershell
# via the pooler (project ref + pooler region are in docs/backend-runbook.md)
psql "postgresql://postgres.<ref>:<password>@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres" -f docs/health-check.sql
```

## Expected healthy output

| Check | Healthy value |
|---|---|
| `open_signals` | `0` or `1` — never more than one (invariant, fixed 2026-10-02) |
| `latest_price_age_sec` | `< 180` (tick runs every minute) |
| `distinct_ideas` | `4` (manual-seed desks a–d) |
| `last_heartbeat_hours` | `< 48` |
| `failed_jobs_24h` | `0` |

---

## The 7-day pause question (open until 2026-10-09)

Supabase Free projects auto-pause after 7 days of low activity, and a paused
project **stops pg_cron** — the pipeline dies silently with no error surfaced
anywhere in the app.

`xv-keepalive` writes one `ops_heartbeat` row per day to prevent that, but
**whether a database write from an Edge Function counts as "user activity" is
not documented by Supabase.** We cannot know until the deadline passes.

### How to check

```sql
-- Days since the oldest heartbeat row was written.
SELECT max(at) AS latest_heartbeat,
       now() - max(at) AS age
  FROM ops_heartbeat;

-- Did cron actually run in the last 10 minutes?
SELECT count(*) AS runs_last_10m
  FROM cron.job_run_details
 WHERE start_time > now() - interval '10 minutes';

-- Is the project paused? There is no API for this, but a paused project
-- returns nothing above and the dashboard shows PAUSED.
```

### The three possible outcomes on ~2026-10-09

| What happens | Meaning | Action |
|---|---|---|
| Heartbeats present **and** cron still firing | The keepalive works. Free tier is viable. | Nothing — keep going |
| Heartbeats present **but** cron stopped | An Edge Function write does **not** count as user activity | Add an external scheduler (GitHub Actions / Cloudflare Workers) calling `xv_invoke_function` over the REST API, **or** upgrade to Pro ($25/mo) |
| Project shows PAUSED in the dashboard | Expected; resume it and apply the row above | Same: external scheduler or Pro |

**Do not assume the heartbeat is enough.** This is the one open risk in the
free-tier design and it cannot be proven before the deadline.

## Other useful probes

```sql
-- Real price source actually in use (expect source = 'gold-api').
SELECT id, status_code, content
  FROM net._http_response ORDER BY id DESC LIMIT 3;

-- Is the seed anchored to the live price, or has it drifted again?
-- entry should sit within a few dollars of the newest price.
SELECT (SELECT price FROM market_snapshots ORDER BY timestamp DESC LIMIT 1) AS price,
       (SELECT min(entry_low) FROM trade_ideas) AS seed_entry,
       (SELECT min(stop_loss) FROM trade_ideas) AS seed_stop;

-- Table sizes against the 500 MB free budget.
SELECT relname, n_live_tup,
       pg_size_pretty(pg_total_relation_size(relid)) AS size
  FROM pg_stat_user_tables
 WHERE n_live_tup > 0
 ORDER BY pg_total_relation_size(relid) DESC;
```

## Rollback

```sql
-- Stop every scheduled job (pipeline goes quiet; data is preserved).
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT jobid, jobname FROM cron.job WHERE jobname LIKE 'xv-%' LOOP
    PERFORM cron.unschedule(r.jobid);
    RAISE NOTICE 'unscheduled %', r.jobname;
  END LOOP;
END $$;
```