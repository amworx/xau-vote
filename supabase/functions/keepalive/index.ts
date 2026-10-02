/**
 * keepalive — scheduled Edge Function, daily (free-tier pause insurance).
 *
 * WHY THIS EXISTS
 * Supabase Free projects auto-pause after 7 days of low activity. A paused
 * project stops pg_cron entirely, so collect-ideas / build-consensus / tick
 * would silently stop firing and the app would show stale or empty data with
 * no error anywhere. Supabase exposes no API to query the paused state, so
 * prevention is the only reliable defence.
 *
 * This function writes ONE row per day into `ops_heartbeat`, which counts as
 * database activity and keeps the project alive. It is deliberately the
 * cheapest possible function: no provider calls, no reads, one upsert.
 *
 * It also prunes the two tables that grow without bound, so the 500 MB free
 * database cannot fill up: `ops_heartbeat` (30 days) and `market_snapshots`
 * (5 days — a 1-minute ticker adds ~1,440 rows/day).
 *
 * A database write from an Edge Function MAY not count as "user activity" for
 * pause purposes — that is undocumented. If the project still pauses after 7
 * days with this job running, the remaining options are an external scheduler
 * (GitHub Actions / Cloudflare Workers) or the Pro plan.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';

const SOURCE = 'keepalive';

Deno.serve(async (_req) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(url, key);

  // One row per source per day: the unique index on (source, day) turns a
  // second run on the same day into an update, not a duplicate row.
  const { error } = await db.from('ops_heartbeat')
    .upsert({ source: SOURCE }, { onConflict: 'source,day' });

  if (error) {
    return Response.json({ ok: false, error: error.message }, { status: 500 });
  }

  // Pruning failures are never fatal: the heartbeat already succeeded, which
  // is the entire purpose of this job.
  const prunes = ['prune_ops_heartbeat', 'prune_market_snapshots', 'prune_market_bars'];
  for (const fn of prunes) {
    const { error: pruneErr } = await db.rpc(fn);
    if (pruneErr) console.log(`keepalive: ${fn} skipped (${pruneErr.message})`);
  }

  return Response.json({ ok: true, source: SOURCE, at: new Date().toISOString() });
});
