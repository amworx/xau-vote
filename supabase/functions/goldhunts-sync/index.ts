/**
 * goldhunts-sync - hourly Gold Hunts session-view sync (directive §2, §9).
 *
 * WHAT THIS IS
 *
 * Pulls the LIVE Gold Hunts feed, archives the raw payload for §3 outcome
 * reconciliation, and upserts label-only rows for the app's EXTERNAL SESSION
 * VIEW. Session context and benchmark only. Nothing here votes, confirms, or
 * supplies XV levels - the calls table has no level columns at all, so that
 * misuse is structurally impossible rather than merely forbidden.
 *
 * SOURCE DISCIPLINE
 *
 * The LIVE endpoint only:
 *   https://ebhodyknnbdhdiezrtsk.supabase.co/functions/v1/refresh-gold-data?dataset=gold-signals
 * The static gold-signals.json file was 11 days stale on the day of review
 * (D-20261006-016) and must never be used. On fetch or validation failure this
 * function fails loudly and writes NOTHING: the previous rows age into STALE
 * by the 6-hour rule instead of being replaced by stale data dressed as fresh.
 *
 * FRESHNESS (directive §2)
 *
 * data_as_of = max published_at across the payload (falling back to the
 * payload's own data_as_of when present and parseable). The app marks STALE
 * when the provider flag is set OR now - data_as_of > 6 hours.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';

const LIVE_URL =
  'https://ebhodyknnbdhdiezrtsk.supabase.co/functions/v1/refresh-gold-data?dataset=gold-signals';

/** Verbatim provider labels. Anything else is rejected, never mapped. */
const KNOWN_DIRECTIONS = new Set([
  'BULLISH',
  'BEARISH',
  'RANGING',
  'SWEEP_THEN_REVERSE',
]);

const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });

function asIso(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const t = Date.parse(v);
  return Number.isNaN(t) ? null : new Date(t).toISOString();
}

Deno.serve(async () => {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    return json({ ok: false, error: 'missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY' }, 500);
  }
  const db = createClient(url, key);
  const now = new Date();

  // 1. Fetch the live feed. Any failure here ends the run with nothing
  // written - see the header for why silent staleness is worse than a 500.
  let payload: Record<string, unknown>;
  try {
    const r = await fetch(LIVE_URL, {
      headers: { accept: 'application/json' },
      signal: AbortSignal.timeout(25_000),
    });
    if (!r.ok) throw new Error(`provider HTTP ${r.status}`);
    payload = (await r.json()) as Record<string, unknown>;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`goldhunts-sync: live fetch failed: ${msg}`);
    return json({ ok: false, error: `live fetch failed: ${msg}` }, 500);
  }

  // 2. Validate shape. A changed schema must fail the run, not half-ingest.
  if (payload['dataset'] !== 'gold-signals' || !Array.isArray(payload['signals'])) {
    console.error('goldhunts-sync: unexpected payload shape');
    return json({ ok: false, error: 'unexpected payload shape' }, 500);
  }
  const signals = payload['signals'] as Record<string, unknown>[];
  const providerStale = payload['stale'] === true;

  // data_as_of: the payload's own field when usable, else the newest call.
  // Never "now" - the fetch time is not the data time.
  let dataAsOf: string | null = asIso(payload['data_as_of']);
  if (!dataAsOf) {
    let best = 0;
    for (const s of signals) {
      const t = typeof s['published_at'] === 'string' ? Date.parse(s['published_at']) : NaN;
      if (!Number.isNaN(t) && t > best) best = t;
    }
    dataAsOf = best > 0 ? new Date(best).toISOString() : null;
  }
  if (!dataAsOf) {
    console.error('goldhunts-sync: no usable timestamp in payload');
    return json({ ok: false, error: 'no usable timestamp in payload' }, 500);
  }

  // 3. Archive the RAW payload first - this is the §3 reconciliation evidence.
  // Stored before any parsing, so the archive is the provider's bytes, not our
  // interpretation of them.
  const { error: snapErr } = await db.from('goldhunts_snapshots').insert({
    data_as_of: dataAsOf,
    provider_stale: providerStale,
    signal_count: signals.length,
    payload,
  });
  if (snapErr) {
    console.error(`goldhunts-sync: snapshot archive failed: ${snapErr.message}`);
    return json({ ok: false, error: `snapshot archive failed: ${snapErr.message}` }, 500);
  }

  // 4. Upsert label-only call rows. Unknown directions are SKIPPED, never
  // mapped: inventing a mapping for a label we do not know is fabrication.
  // Levels are dropped on the floor here - there is nowhere to put them.
  let open = 0;
  let skipped = 0;
  for (const s of signals) {
    const id = typeof s['id'] === 'string' ? s['id'] : null;
    const direction = typeof s['direction'] === 'string' ? s['direction'] : null;
    const session = typeof s['session'] === 'string' ? s['session'] : null;
    const status = typeof s['status'] === 'string' ? s['status'] : 'open';
    if (!id || !direction || !session) { skipped++; continue; }
    if (!KNOWN_DIRECTIONS.has(direction)) {
      console.error(`goldhunts-sync: unknown direction label, skipping (not mapping): ${direction}`);
      skipped++;
      continue;
    }
    const sessionDate =
      typeof s['session_date'] === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s['session_date'])
        ? s['session_date']
        : null;
    const { error: upErr } = await db.from('goldhunts_calls').upsert(
      {
        provider_id: id,
        direction,
        session,
        session_date: sessionDate,
        published_at: asIso(s['published_at']),
        data_as_of: dataAsOf,
        provider_stale: providerStale,
        status,
        fetched_at: now.toISOString(),
      },
      { onConflict: 'provider_id' },
    );
    if (upErr) {
      console.error(`goldhunts-sync: call upsert failed for ${id}: ${upErr.message}`);
      return json({ ok: false, error: `call upsert failed: ${upErr.message}` }, 500);
    }
    if (status === 'open') open++;
  }

  // 5. Feed state + prune snapshots past 72h (sessions close daily; 72h covers
  // every open call's window plus its scoring, without growing the archive).
  const { error: stateErr } = await db.from('goldhunts_feed_state').upsert(
    {
      id: true,
      fetched_at: now.toISOString(),
      data_as_of: dataAsOf,
      provider_stale: providerStale,
      signal_count: signals.length,
      open_count: open,
    },
    { onConflict: 'id' },
  );
  if (stateErr) {
    console.error(`goldhunts-sync: feed state failed: ${stateErr.message}`);
    return json({ ok: false, error: `feed state failed: ${stateErr.message}` }, 500);
  }
  await db.from('goldhunts_snapshots')
    .delete()
    .lt('fetched_at', new Date(now.getTime() - 72 * 3600 * 1000).toISOString());

  return json({
    ok: true,
    fetched: now.toISOString(),
    data_as_of: dataAsOf,
    provider_stale: providerStale,
    signals: signals.length,
    open,
    skipped,
  });
});