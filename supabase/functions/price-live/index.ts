/**
 * price-live - on-demand live XAUUSD price with a server-side cache.
 *
 * WHY THIS EXISTS
 *
 * The Radar price must move with the market. Two facts made a client-side poll
 * the wrong design:
 *
 *   1. The evidence table (`market_snapshots`) is written by `tick` once a
 *      minute, and pg_cron cannot run sub-minute. Polling it faster cannot beat
 *      a producer that only moves once a minute.
 *   2. The provider rate-limits by client IP. Measured 2026-10-06: sixteen
 *      requests at 4s spacing from a workstation all returned 200, while the
 *      same cadence from the phone returned 429 every time. A design that works
 *      on the developer's connection and fails on a real user's phone is not a
 *      design.
 *
 * So the provider is called HERE, at most once per CACHE_TTL, and every client
 * reads that one result. Upstream request volume becomes independent of the
 * number of people using the app.
 *
 * LICENCE
 *
 * gold-api.com permits commercial use including in mobile apps. This is the
 * permitted path. Note the contrast with the spread feed: the OANDA ladder is
 * internal-use-only (D-20261006-013) and is NEVER touched by this function.
 *
 * NEVER FABRICATE
 *
 * If the provider fails, this returns the newest stored snapshot and says
 * `live: false`, so the app can label a stale number as stale. It never invents
 * a price, and it never returns the seed row as if it were a quote.
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';

/**
 * How long a cached price is served before going upstream again.
 *
 * The provider republishes on roughly a 30-second cycle - verified by watching
 * its own `updatedAt` field advance in 30s steps. Polling it faster than that
 * cannot produce a newer number, it just spends the quota to re-read the same
 * value, so a 10s cache costs nothing in freshness and halves upstream traffic.
 * Ten seconds also keeps the client's display within one cache window of the
 * provider's newest value, which is the actual limit on how live this can be.
 */
const CACHE_TTL_MS = 10_000;

const PROVIDER_URL = 'https://api.gold-api.com/price/XAU';

const SYMBOL = 'XAUUSD';

interface Body {
  price: number | null;
  live: boolean;
  source: string;
  /** Age of the returned number in whole seconds, so the client can show it. */
  ageSeconds: number;
  measuredAt: string | null;
}

const json = (b: Body, status = 200) =>
  new Response(JSON.stringify(b), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      // A price this short-lived must never sit in a shared cache.
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
    },
  });

function positive(n: unknown): n is number {
  return typeof n === 'number' && Number.isFinite(n) && n > 0;
}

Deno.serve(async () => {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    return json({ price: null, live: false, source: 'none', ageSeconds: 0, measuredAt: null }, 500);
  }
  const db = createClient(url, key);

  const readCache = async () => {
    const { data } = await db
      .from('live_price_cache')
      .select('price,source,measured_at')
      .eq('id', true)
      .maybeSingle();
    const row = data as { price?: unknown; source?: unknown; measured_at?: unknown } | null;
    if (!positive(row?.price)) return null;
    // `seed` is the placeholder row from migration 0018. It is not a quote and
    // must never be served as one.
    if (row.source === 'seed') return null;
    return {
      price: Number(row.price),
      source: String(row.source),
      measuredAt: new Date(String(row.measured_at)).toISOString(),
      ageMs: Date.now() - new Date(String(row.measured_at)).getTime(),
    };
  };

  const cached = await readCache();
  if (cached && cached.ageMs < CACHE_TTL_MS) {
    return json({
      price: cached.price,
      live: true,
      source: cached.source,
      ageSeconds: Math.floor(cached.ageMs / 1000),
      measuredAt: cached.measuredAt,
    });
  }

  // Cache is missing or stale: go upstream.
  try {
    const headers: Record<string, string> = {};
    // Sent only when configured, so the anonymous free tier is never handed a
    // credential it does not expect.
    const k = Deno.env.get('GOLD_API_KEY');
    if (k) headers['x-access-token'] = k;

    const r = await fetch(PROVIDER_URL, { headers });
    if (!r.ok) throw new Error(`provider HTTP ${r.status}`);
    const j = (await r.json()) as { price?: unknown; updatedAt?: unknown };
    if (!positive(j.price)) throw new Error('provider returned no usable price');

    const price = Number(j.price);
    const measuredAt = typeof j.updatedAt === 'string' ? j.updatedAt : new Date().toISOString();

    await db
      .from('live_price_cache')
      .upsert(
        { id: true, symbol: SYMBOL, price, source: 'gold-api', measured_at: measuredAt },
        { onConflict: 'id' },
      );

    // Age comes from the PROVIDER's own timestamp, not from the fact that we
    // just made the call. It republishes on a slower cycle than clients poll, so
    // a fresh fetch can still hand back a number that is 30s old. Reporting 0
    // here would overstate the freshness of the display by up to half a minute.
    return json({
      price,
      live: true,
      source: 'gold-api',
      ageSeconds: Math.max(0, Math.floor((Date.now() - new Date(measuredAt).getTime()) / 1000)),
      measuredAt,
    });
  } catch {
    // Provider failed. Serve the previous number if we have one, clearly marked
    // as not live so the app can label it honestly. A stale price is useful; a
    // mislabelled one is not.
    if (cached) {
      return json({
        price: cached.price,
        live: false,
        source: cached.source,
        ageSeconds: Math.floor(cached.ageMs / 1000),
        measuredAt: cached.measuredAt,
      });
    }

    // Nothing cached either: fall back to the last recorded snapshot rather than
    // showing nothing, again explicitly marked as not live.
    const { data } = await db
      .from('market_snapshots')
      .select('price,timestamp')
      .eq('symbol', SYMBOL)
      .order('timestamp', { ascending: false })
      .limit(1)
      .maybeSingle();
    const row = data as { price?: unknown; timestamp?: unknown } | null;
    if (!positive(row?.price)) {
      return json({ price: null, live: false, source: 'none', ageSeconds: 0, measuredAt: null }, 503);
    }
    const measuredAt = String(row.timestamp);
    return json({
      price: Number(row.price),
      live: false,
      source: 'stored-snapshot',
      ageSeconds: Math.max(0, Math.floor((Date.now() - new Date(measuredAt).getTime()) / 1000)),
      measuredAt,
    });
  }
});