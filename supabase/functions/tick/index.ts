/**
 * tick — scheduled Edge Function, runs every minute (TASK-04 T4.4/T4.5).
 *
 * 1. Fetches the current XAUUSD price (Gold API when GOLD_API_KEY is set,
 *    otherwise the last market_snapshot — never fabricates a price).
 * 2. Stores a market_snapshot row.
 * 3. Advances every open consensus signal through the spec §14 lifecycle:
 *    developing → ready (price in entry zone) → confirmed (5M structure
 *    flags; MVP: zone hold on the next tick) → active → tp1Hit/tp2Hit/tp3Hit,
 *    or invalidated (close beyond SL) / expired (past expires_at).
 * 4. Queues FCM notifications for transitions when FCM_* env is present;
 *    silently skips dispatch otherwise (logged, never crashing the tick).
 *
 * Price chain (Gate G3, resolved 2026-10-01 by live endpoint testing):
 *   1. `gold-api.com` — verified working anonymously, no key required. When
 *      `GOLD_API_KEY` is set it is sent as `x-access-token`, which the paid
 *      tier expects. This is the primary source.
 *   2. `goldprice.dev` — optional secondary (`GOLDPRICE_DEV_ENABLED=true`).
 *   3. Last `market_snapshots` row — last-resort fallback so a provider outage
 *      degrades to a stale price rather than skipping the tick entirely.
 * A price is NEVER invented: if all three fail the tick reports `skipped`.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
 *      GOLD_API_KEY (optional), GOLDPRICE_DEV_ENABLED (optional),
 *      FCM_PROJECT_ID + FCM_KEY (optional)
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  transition,
  toDbStatus,
  toEngineStatus,
  type SignalStatus,
} from '../_shared/engine.ts';

/**
 * Surprise thresholds, mirrored from fetch-events (canonical).
 * Kept local (not imported) because importing fetch-events/index.ts would
 * execute its top-level Deno.serve. 'hot'|'cold'|'inline'|null.
 */
function surpriseFlag(title: string, actual: number, forecast: number): 'hot' | 'cold' | 'inline' {
  const t = title.toLowerCase();
  const tol = t.includes('non-farm') || t.includes('nfp') || t.includes('payroll')
    ? 50
    : (t.startsWith('cpi') || t.includes('cpi') ? 0.2 : Math.abs(forecast) * 0.1);
  const d = actual - forecast;
  if (Math.abs(d) <= tol) return 'inline';
  return d > 0 ? 'hot' : 'cold';
}

/**
 * OPEN statuses, in the schema's SCREAMING_CASE.
 *
 * The Dart engine (`SignalStatus`) uses camelCase (`tp1Hit`) while the
 * `consensus_signals.status` CHECK constraint stores SCREAMING_CASE
 * (`TP1_HIT`) — see migration 0001 line 92. Queries MUST use the DB form.
 */
const OPEN = ['DEVELOPING', 'READY', 'CONFIRMED', 'ACTIVE', 'TP1_HIT', 'TP2_HIT'] as const;

interface Signal {
  id: string;
  direction: 'long' | 'short';
  entry_low: number;
  entry_high: number;
  stop_loss: number;
  tp1: number | null;
  tp2: number | null;
  tp3: number | null;
  status: SignalStatus;
  expires_at: string;
  updated_at: string;
}

/** Provider chain result: where the price came from, for auditability. */
export interface Quote {
  price: number;
  source: 'gold-api' | 'goldprice.dev' | 'snapshot';
  /** Populated only by the snapshot fallback — the row is stale by definition. */
  stale: boolean;
}

const positive = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v) && v > 0;

/**
 * Primary: gold-api.com.
 *
 * Verified 2026-10-01 from this machine — responds anonymously with no key
 * (`{"price":4178.5,"symbol":"XAU",...}`), and tolerates an `x-access-token`
 * header for the paid tier. The header is sent ONLY when a key is configured
 * so the anonymous free tier is never sent a bogus credential.
 */
async function fromGoldApi(): Promise<number | null> {
  try {
    const headers: Record<string, string> = {};
    const key = Deno.env.get('GOLD_API_KEY');
    if (key) headers['x-access-token'] = key;
    const r = await fetch('https://api.gold-api.com/price/XAU', { headers });
    if (!r.ok) return null;
    const j = await r.json() as { price?: unknown };
    return positive(j.price) ? j.price : null;
  } catch {
    return null;
  }
}

/**
 * Secondary: goldprice.dev.
 *
 * Opt-in via `GOLDPRICE_DEV_ENABLED=true` because its Free tier is documented
 * as "internal use" and its live JSON carries no bid/ask. NOTE the host is
 * `api.goldprice.dev` — `goldprice.dev/v1/...` returns 404.
 */
async function fromGoldPriceDev(): Promise<number | null> {
  if (Deno.env.get('GOLDPRICE_DEV_ENABLED') !== 'true') return null;
  try {
    const r = await fetch('https://api.goldprice.dev/v1/prices?symbol=XAU-USD-SPOT');
    if (!r.ok) return null;
    const j = await r.json() as { symbols?: Array<{ price?: unknown; is_stale?: boolean }> };
    const first = j.symbols?.[0];
    if (!first || first.is_stale === true) return null;
    return positive(first.price) ? Number(first.price) : null;
  } catch {
    return null;
  }
}

/** Last-resort: the newest stored snapshot, explicitly flagged stale. */
async function fromSnapshot(db: ReturnType<typeof createClient>): Promise<Quote | null> {
  const { data } = await db.from('market_snapshots')
    .select('price').eq('symbol', 'XAUUSD')
    .order('timestamp', { ascending: false }).limit(1).maybeSingle();
  const row = data as { price?: unknown } | null;
  if (!positive(row?.price)) return null;
  return { price: row.price, source: 'snapshot', stale: true };
}

/**
 * Resolve the current XAUUSD price, provider first, snapshot last.
 * Throws only when every source fails — the caller then reports `skipped`
 * rather than storing a fabricated price (product rule 2).
 */
export async function currentPrice(db: ReturnType<typeof createClient>): Promise<Quote> {
  const gold = await fromGoldApi();
  if (gold !== null) return { price: gold, source: 'gold-api', stale: false };

  const dev = await fromGoldPriceDev();
  if (dev !== null) return { price: dev, source: 'goldprice.dev', stale: false };

  const snap = await fromSnapshot(db);
  if (snap) return snap;

  throw new Error('No market price available (providers failed and no snapshot exists). Tick skipped.');
}

const inZone = (p: number, s: Signal): boolean => p >= s.entry_low && p <= s.entry_high;
const breached = (p: number, s: Signal): boolean =>
  s.direction === 'long' ? p < s.stop_loss : p > s.stop_loss;

Deno.serve(async (_req) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(url, key);
  const now = new Date();

  let quote;
  try {
    quote = await currentPrice(db);
  } catch (e) {
    return Response.json({ ok: true, skipped: String(e) });
  }
  // bid/ask stay null: none of the free price sources publish a genuine
  // spread, and the consensus engine runs on a single mid. Inventing one
  // would violate the never-fabricate rule (product rule 2).
  await db.from('market_snapshots').insert({
    symbol: 'XAUUSD', price: quote.price, bid: null, ask: null, timestamp: now.toISOString(),
  });

  const { data, error } = await db.from('consensus_signals')
    .select('*').eq('symbol', 'XAUUSD').in('status', OPEN as unknown as string[]);
  if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });

  const transitions: { id: string; from: string; to: string }[] = [];
  const notify: { id: string; kind: string; price: number }[] = [];
  for (const row of (data ?? []) as Signal[]) {
    // Row statuses are SCREAMING_CASE in the DB; the shared engine speaks
    // camelCase. Translate at the boundary so the lifecycle logic below stays
    // in the engine's vocabulary and only I/O uses the schema's.
    const s: Signal = { ...row, status: toEngineStatus(row.status) };
    let next: SignalStatus | null = null;
    if (new Date(s.expires_at).getTime() <= now.getTime() && (s.status === 'ready' || s.status === 'confirmed')) {
      next = 'expired';
    } else if (breached(quote.price, s)) {
      next = 'invalidated';
    } else if (s.status === 'developing' && inZone(quote.price, s)) {
      next = 'ready';
    } else if (s.status === 'ready') {
      next = 'confirmed'; // MVP: zone hold across one tick = 5M structure proxy
    } else if (s.status === 'confirmed') {
      next = 'active';
    } else if (s.status === 'active' && s.tp1 !== null &&
      (s.direction === 'long' ? quote.price >= s.tp1 : quote.price <= s.tp1)) {
      next = 'tp1Hit';
    } else if (s.status === 'tp1Hit' && s.tp2 !== null &&
      (s.direction === 'long' ? quote.price >= s.tp2 : quote.price <= s.tp2)) {
      next = 'tp2Hit';
    } else if (s.status === 'tp2Hit' && s.tp3 !== null &&
      (s.direction === 'long' ? quote.price >= s.tp3 : quote.price <= s.tp3)) {
      next = 'tp3Hit';
    }
    if (next) {
      try {
        transition(s.status, next);
      } catch { continue; }
      const { error: upErr } = await db.from('consensus_signals')
        .update({ status: toDbStatus(next), updated_at: now.toISOString() }).eq('id', s.id);
      if (!upErr) {
        transitions.push({ id: s.id, from: s.status, to: next });
        if (['confirmed', 'invalidated', 'tp1Hit', 'tp2Hit', 'tp3Hit'].includes(next)) {
          notify.push({ id: s.id, kind: next, price: quote.price });
        }
      }
    }
  }

  // FCM dispatch (T4.5) via the legacy HTTP API (server key only).
  // Absent credentials → logged skip, never a crash.
  // TASK-07: event notifications (60m/15m HIGH warnings, blackout-lift,
  // surprise alerts — addendum §4) ride the same transport.
  const eventNotify: { title: string; body: string; eventId: string; kind: string }[] = [];

  // Surprise detection: actuals landed but no flag computed yet.
  const { data: pending } = await db.from('economic_events')
    .select('id,title,actual,forecast')
    .not('actual', 'is', null)
    .not('forecast', 'is', null)
    .is('surprise', null);
  const freshSurprises: { id: string; title: string }[] = [];
  for (const e of ((pending ?? []) as { id: string; title: string; actual: number; forecast: number }[])) {
    const flag = surpriseFlag(e.title, Number(e.actual), Number(e.forecast));
    await db.from('economic_events').update({ surprise: flag }).eq('id', e.id);
    if (flag === 'hot' || flag === 'cold') {
      freshSurprises.push({ id: e.id, title: e.title });
      eventNotify.push({
        title: `${e.title} surprise — expect volatility`,
        body: `Actual ${e.actual} vs ${e.forecast} forecast · ${now.toISOString()}`,
        eventId: e.id,
        kind: 'surprise',
      });
    }
  }

  // 60m / 15m HIGH warnings + blackout-lift notice (USD HIGH only).
  const { data: upcoming } = await db.from('economic_events')
    .select('id,title,starts_at')
    .eq('impact', 'HIGH')
    .gte('starts_at', new Date(now.getTime() - 20 * 60000).toISOString())
    .lte('starts_at', new Date(now.getTime() + 65 * 60000).toISOString());
  for (const e of ((upcoming ?? []) as { id: string; title: string; starts_at: string }[])) {
    const mins = Math.round((new Date(e.starts_at).getTime() - now.getTime()) / 60000);
    if (mins >= 55 && mins <= 65) {
      eventNotify.push({
        title: `⚠ ${e.title} in 60 min — new signals pause 30 min before`,
        body: `${e.title} @ ${e.starts_at} · ${now.toISOString()}`,
        eventId: e.id,
        kind: 'warn60',
      });
    } else if (mins >= 10 && mins <= 20) {
      eventNotify.push({
        title: `⚠ ${e.title} in 15 min — blackout active`,
        body: `${e.title} @ ${e.starts_at} · ${now.toISOString()}`,
        eventId: e.id,
        kind: 'warn15',
      });
    } else if (mins >= -20 && mins <= -14) {
      eventNotify.push({
        title: 'Event window passed — scanning for fresh 15M consensus',
        body: `${e.title} released @ ${e.starts_at} · ${now.toISOString()}`,
        eventId: e.id,
        kind: 'lifted',
      });
    }
  }

  // Post-surprise context: signals confirmed this tick within 60 min after
  // a hot/cold surprise (display flag only — never votes, rule 9).
  const { data: recentSurprises } = await db.from('economic_events')
    .select('id,title')
    .in('surprise', ['hot', 'cold'])
    .gte('starts_at', new Date(now.getTime() - 60 * 60000).toISOString());
  const postSurpriseIds: string[] = ((recentSurprises ?? []).length > 0)
    ? transitions.filter((t) => t.to === 'ready' || t.to === 'confirmed').map((t) => t.id)
    : [];
  if (postSurpriseIds.length > 0) {
    console.log(`tick: post-surprise context on signals ${postSurpriseIds.join(',')}`);
  }

  let dispatched = 0;
  let eventDispatched = 0;
  const fcmKey = Deno.env.get('FCM_KEY');
  const sendFcm = async (title: string, body: string, data: Record<string, string>): Promise<boolean> => {
    if (!fcmKey) return false;
    try {
      const r = await fetch('https://fcm.googleapis.com/fcm/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `key=${fcmKey}` },
        body: JSON.stringify({
          to: '/topics/xau-signals',
          notification: { title, body },
          data,
        }),
      });
      return r.ok;
    } catch { return false; /* per-message failure must not break the tick */ }
  };
  if (notify.length > 0 && fcmKey) {
    const titles: Record<string, string> = {
      confirmed: 'XAUUSD setup confirmed on 5M',
      invalidated: 'XAUUSD setup invalidated',
      tp1Hit: 'XAUUSD TP1 reached',
      tp2Hit: 'XAUUSD TP2 reached',
      tp3Hit: 'XAUUSD TP3 reached',
    };
    for (const n of notify) {
      const ok = await sendFcm(
        titles[n.kind] ?? 'XV update',
        `${n.kind} at ${n.price} · ${now.toISOString()}`,
        { signal_id: n.id, kind: n.kind, price: String(n.price) },
      );
      if (ok) dispatched++;
    }
  }
  for (const n of eventNotify) {
    const ok = await sendFcm(n.title, n.body, { event_id: n.eventId, kind: n.kind });
    if (ok) eventDispatched++;
  }
  return Response.json({
    ok: true, price: quote.price, source: quote.source, stalePrice: quote.stale,
    transitions, queued: notify, dispatched,
    eventNotifications: eventNotify, eventDispatched, freshSurprises, postSurpriseIds,
    at: now.toISOString(),
  });
});
