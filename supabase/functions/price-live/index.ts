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
 * PROVIDERS (in order)
 *
 *   1. biquote.io (PRIMARY, D-20261007-024): free, keyless, ToS explicitly
 *      permits commercial display/use with no signup (no raw-feed resale, no
 *      misrepresentation — we display inside the product only, with
 *      attribution). Tick-fresh quotes (`quoteAgeSeconds` ~1s verified
 *      2026-10-07) via plain REST; the unmetered SignalR stream is a later
 *      step, not this one. Accepted only when the quote is fresh and not
 *      flagged stale — a closed-market quote must fail into the fallback,
 *      never onto the screen as live.
 *   2. gold-api.com (FALLBACK): commercial use permitted including mobile
 *      apps. Republishes on roughly a 30-second cycle.
 *
 * MID ONLY
 *
 * biquote publishes bid/ask/spread alongside mid. The venue spread is an
 * execution number, not a display number (same lesson as the OANDA ladder,
 * D-20261006-013): only `mid` is stored, cached and served. Bid/ask never
 * touch the database or the response.
 *
 * NEVER FABRICATE
 *
 * If both providers fail, this returns the newest stored snapshot and says
 * `live: false`, so the app can label a stale number as stale. It never invents
 * a price, and it never returns the seed row as if it were a quote.
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';

/**
 * How long a cached price is served before going upstream again.
 *
 * The primary (biquote) publishes tick-fresh quotes, so a 5s cache keeps the
 * display within seconds of the market at ~12 upstream requests a minute —
 * nothing against a 15,000/min limit. The fallback (gold-api) republishes on
 * roughly a 30-second cycle; a 5s cache re-reads its value a few times per
 * cycle, which costs nothing and keeps the code path identical.
 */
const CACHE_TTL_MS = 5_000;

const BIQUOTE_URL = 'https://biquote.io/api/XAUUSD';
const GOLD_API_URL = 'https://api.gold-api.com/price/XAU';

/**
 * A biquote quote is accepted only when it proves itself fresh: not flagged
 * stale and at most this old by its own clock. A closed market, a stuck feed
 * or a slow edge all age the quote past this in seconds, and each must fail
 * into the fallback — never onto the screen as live.
 */
const MAX_QUOTE_AGE_S = 20;

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

interface FreshQuote {
  price: number;
  measuredAt: string;
  ageSeconds: number;
}

/**
 * biquote primary read. Returns null on ANY doubt (network, shape, staleness,
 * age) so the caller falls through to gold-api. Never throws: a primary that
 * throws would skip the fallback, and a missed fallback is an outage.
 *
 * Only `mid` is read. `bid`/`ask`/`spread` are execution numbers from a
 * broker feed and must never be stored, cached or served (D-20261007-024).
 */
async function tryBiquote(): Promise<FreshQuote | null> {
  try {
    const r = await fetch(BIQUOTE_URL, {
      headers: { accept: 'application/json' },
      signal: AbortSignal.timeout(8_000),
    });
    if (!r.ok) return null;
    const j = (await r.json()) as {
      mid?: unknown;
      stale?: unknown;
      quoteAgeSeconds?: unknown;
      lastQuoteAt?: unknown;
      timestamp?: unknown;
    };
    if (!positive(j.mid)) return null;
    if (j.stale === true) return null;
    const measuredAt =
      typeof j.lastQuoteAt === 'string'
        ? j.lastQuoteAt
        : typeof j.timestamp === 'string'
          ? j.timestamp
          : null;
    if (!measuredAt) return null;
    const ageSeconds = Math.floor((Date.now() - new Date(measuredAt).getTime()) / 1000);
    if (!Number.isFinite(ageSeconds) || ageSeconds < 0 || ageSeconds > MAX_QUOTE_AGE_S) return null;
    // quoteAgeSeconds is the provider's own claim; when present it must agree
    // the quote is fresh. A provider that contradicts itself is not trusted.
    if (typeof j.quoteAgeSeconds === 'number' && j.quoteAgeSeconds > MAX_QUOTE_AGE_S) return null;
    return { price: Number(j.mid), measuredAt, ageSeconds };
  } catch {
    return null;
  }
}

Deno.serve(async () => {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    return json({ price: null, live: false, source: 'none', ageSeconds: 0, measuredAt: null }, 500);
  }
  const db = createClient(url, key);

  const writeCache = async (price: number, source: string, measuredAt: string) => {
    await db
      .from('live_price_cache')
      .upsert(
        { id: true, symbol: SYMBOL, price, source, measured_at: measuredAt },
        { onConflict: 'id' },
      );
  };

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

  // Cache is missing or stale: go upstream, primary first.
  const biquote = await tryBiquote();
  if (biquote) {
    await writeCache(biquote.price, 'biquote', biquote.measuredAt);
    return json({
      price: biquote.price,
      live: true,
      source: 'biquote',
      ageSeconds: biquote.ageSeconds,
      measuredAt: biquote.measuredAt,
    });
  }

  try {
    const headers: Record<string, string> = {};
    // Sent only when configured, so the anonymous free tier is never handed a
    // credential it does not expect.
    const k = Deno.env.get('GOLD_API_KEY');
    if (k) headers['x-access-token'] = k;

    const r = await fetch(GOLD_API_URL, { headers });
    if (!r.ok) throw new Error(`provider HTTP ${r.status}`);
    const j = (await r.json()) as { price?: unknown; updatedAt?: unknown };
    if (!positive(j.price)) throw new Error('provider returned no usable price');

    const price = Number(j.price);
    const measuredAt = typeof j.updatedAt === 'string' ? j.updatedAt : new Date().toISOString();

    await writeCache(price, 'gold-api', measuredAt);

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
    // Both providers failed. Serve the previous number if we have one, clearly
    // marked as not live so the app can label it honestly. A stale price is
    // useful; a mislabelled one is not.
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