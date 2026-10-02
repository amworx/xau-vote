// Aggregates confirmed ticks into closed OHLC bars for every timeframe the
// expert engine needs (methodology §1.2, §22).
//
// This is the storage half of the technical engine. Until XV had bars it could
// only store single prices, which makes EMA/RSI/MACD/ADX/ATR and market
// structure impossible — indicators confirm, they never initiate, so there was
// nothing to confirm with.
//
// Design notes:
//   * The still-forming bar IS persisted (is_closed = false) because the
//     lifecycle/tick loop needs the live price, but every indicator read
//     filters on is_closed = true.
//   * Aggregation uses only ticks at or before the bar boundary, so a bar is
//     never contaminated by later ticks.
//   * Upsert is idempotent: re-running for the same window converges rather
//     than duplicating (there is a unique index on symbol/timeframe/open_time).

import { createClient } from 'jsr:@supabase/supabase-js@2';

interface BarRow {
  symbol: string;
  timeframe: string;
  open_time: string;
  open: number;
  high: number;
  low: number;
  close: number;
  is_closed: boolean;
  source: string;
  quality: string;
}

const TIMEFRAMES: { name: string; minutes: number }[] = [
  { name: '5m', minutes: 5 },
  { name: '15m', minutes: 15 },
  { name: '30m', minutes: 30 },
  { name: '1h', minutes: 60 },
];

const MS_PER_MIN = 60_000;

function floorTo(ms: number, minutes: number): number {
  const size = minutes * MS_PER_MIN;
  return Math.floor(ms / size) * size;
}

interface Agg {
  open: number;
  high: number;
  low: number;
  close: number;
  firstTs: number;
  lastTs: number;
}

function aggregate(
  ticks: { price: number; ts: number }[],
): Agg | null {
  if (ticks.length === 0) return null;
  const sorted = [...ticks].sort((a, b) => a.ts - b.ts);
  let high = -Infinity;
  let low = Infinity;
  for (const t of sorted) {
    if (t.price > high) high = t.price;
    if (t.price < low) low = t.price;
  }
  return {
    open: sorted[0].price,
    high,
    low,
    close: sorted[sorted.length - 1].price,
    firstTs: sorted[0].ts,
    lastTs: sorted[sorted.length - 1].ts,
  };
}

Deno.serve(async () => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(url, key);

  const now = Date.now();
  const lookbackMs = 4 * 60 * MS_PER_MIN; // covers the widest bar (1h)
  const fromIso = new Date(now - lookbackMs).toISOString();

  const { data, error } = await db
    .from('market_snapshots')
    .select('price, timestamp')
    .eq('symbol', 'XAUUSD')
    .gte('timestamp', fromIso)
    .order('timestamp', { ascending: true });

  if (error) {
    return Response.json({ ok: false, error: error.message }, { status: 500 });
  }

  const ticks = ((data ?? []) as { price: number; timestamp: string }[]).map((r) => ({
    price: Number(r.price),
    ts: new Date(r.timestamp).getTime(),
  }));

  if (ticks.length === 0) {
    return Response.json({ ok: true, skipped: 'no ticks in window', ticks: 0 });
  }

  const rows: BarRow[] = [];

  for (const tf of TIMEFRAMES) {
    const buckets = new Map<number, { price: number; ts: number }[]>();
    for (const t of ticks) {
      const b = floorTo(t.ts, tf.minutes);
      const list = buckets.get(b);
      if (list) list.push(t);
      else buckets.set(b, [t]);
    }

    for (const [bucketMs, bucketTicks] of buckets) {
      const agg = aggregate(bucketTicks);
      if (!agg) continue;
      const openTime = bucketMs + tf.minutes * MS_PER_MIN;
      // A bar is closed only once its own end boundary has passed. The
      // in-progress bar is still stored so the UI can show live price.
      const isClosed = now >= openTime;
      rows.push({
        symbol: 'XAUUSD',
        timeframe: tf.name,
        open_time: new Date(bucketMs).toISOString(),
        open: agg.open,
        high: agg.high,
        low: agg.low,
        close: agg.close,
        is_closed: isClosed,
        source: 'gold-api',
        quality: 'primary',
      });
    }
  }

  if (rows.length === 0) {
    return Response.json({ ok: true, skipped: 'nothing to aggregate', ticks: ticks.length });
  }

  const { error: upErr } = await db
    .from('market_bars')
    .upsert(rows, { onConflict: 'symbol,timeframe,open_time' });

  if (upErr) {
    return Response.json({ ok: false, error: upErr.message }, { status: 500 });
  }

  const closed = rows.filter((r) => r.is_closed).length;
  return Response.json({
    ok: true,
    ticks: ticks.length,
    bars_written: rows.length,
    bars_closed: closed,
    timeframes: TIMEFRAMES.map((t) => t.name),
  });
});