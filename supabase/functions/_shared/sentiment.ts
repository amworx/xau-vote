/**
 * Sentiment layer scoring — pure logic, shared by the `sentiment-layers` Edge
 * Function and its tests.
 *
 * Kept free of Deno globals and network calls so it can be run with Node's
 * type stripping (`node sentiment_test.ts`), matching `_shared/engine.ts`.
 *
 * Every rule here traces to
 * `instruction/XAUUSD_IMPLEMENTATION_READY_METHODOLOGY.md` §1.6 and §5.
 */

// ── §5.1 weights, verbatim from the methodology ──────────────────────────────
export const WEIGHTS = {
  policy: 35,
  positioning: 25,
  gold_fundamentals: 20,
  market_implied: 20,
} as const;

export const HORIZONS = {
  policy: 'days-weeks',
  positioning: 'weeks',
  gold_fundamentals: 'months',
  market_implied: 'hours-days',
} as const;

/** §1.6: percentile over 156 weeks (3 years). */
export const PERCENTILE_WEEKS = 156;

/** CFTC contract market code for COMEX gold. */
export const GOLD_CODE = '088691';

/**
 * §5.3 COT score, banded on the 156-week percentile of managed money.
 *
 * The methodology's band list overlaps: a percentile of 32 satisfies both
 * "20-60 → 0" and "20-40 → −1". This resolves it by letting the NARROWER band
 * win, so the score carries the most information the percentile actually
 * provides. A reading in the lower third of its three-year range should not
 * pass as merely neutral.
 *
 *   < 20      → −1   (−2 reserved for a bearish trend confirming it)
 *   20–40     → −1
 *   40–60     →  0
 *   60–80     → +1
 *   > 80      → +1   (+2 reserved for a bullish trend confirming it)
 *
 * §5.3 attaches the ±2 extremes to a price-trend leg and separately flags
 * POSITIONING_DIVERGENCE when trend and positioning disagree. Callers that have
 * not read price pass `trend` undefined: the score then never claims ±2, and the
 * caller records `trend_confirmed: false`. Claiming the trend leg from
 * positioning alone would invent a confirmation that did not happen.
 */
export function cotScore(percentile: number, trend?: 'bullish' | 'bearish'): number {
  if (percentile < 20) return trend === 'bearish' ? -2 : -1;
  if (percentile < 40) return -1;
  if (percentile < 60) return 0;
  if (percentile <= 80) return 1;
  return trend === 'bullish' ? 2 : 1;
}

/** §1.6: fraction of the window strictly below `value`, as a percentage. */
export function percentileRank(series: number[], value: number): number {
  if (series.length === 0) return 50;
  let below = 0;
  for (const v of series) if (v < value) below++;
  return (below / series.length) * 100;
}

/** Alignment: −1 bearish, 0 neutral, +1 bullish. */
export function alignmentOf(score: number): number {
  return score > 0 ? 1 : score < 0 ? -1 : 0;
}

/**
 * Treasury ships dates as MM/DD/YYYY with no timezone. `new Date('10/02/2026')`
 * reads that as LOCAL midnight, so east of UTC the value lands on the previous
 * day and the recorded `measured_at` — plus any staleness check derived from it
 * — shifts silently. Split and rebuild in UTC so the reading is identical
 * everywhere. Returns an ISO date, or null if the shape is unrecognised.
 */
export function parseTreasuryDate(raw: string): string | null {
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(raw.trim());
  if (!m) return null;
  const iso = `${m[3]}-${m[1].padStart(2, '0')}-${m[2].padStart(2, '0')}`;
  return Number.isNaN(new Date(iso + 'T00:00:00Z').getTime()) ? null : iso;
}

export interface TreasuryRow {
  date: string;
  real5y: number | null;
  real10y: number | null;
}

/**
 * §1.3 / §5.1 market-implied: rising real yields tighten financial conditions
 * and weigh on gold (it pays no yield); falling real weighs the other way.
 *
 * The impulse is the change in the 10-year real yield across the last six
 * usable observations — five sessions back from the latest — in basis points.
 * Anything inside ±5bp is scored 0 rather than read as a signal, because a move
 * that small is noise on a daily series, and scoring it would manufacture
 * alignment out of noise.
 */
export function realYieldImpulse(series: TreasuryRow[]): {
  impulse: number | null;
  alignment: number | null;
  latest: TreasuryRow | null;
  prior: TreasuryRow | null;
} {
  const usable = series.filter((r) => r.real10y !== null);
  const latest = usable.length > 0 ? usable[usable.length - 1] : null;
  const prior = usable.length > 0 ? usable[Math.max(0, usable.length - 6)] : null;
  if (!latest || latest.real10y === null || !prior || prior.real10y === null) {
    return { impulse: null, alignment: null, latest, prior };
  }
  const bp = (latest.real10y - prior.real10y) * 100; // percent -> basis points
  const impulse = Math.round(bp * 10) / 10;
  const alignment = Math.abs(bp) < 5 ? 0 : bp > 0 ? -1 : 1;
  return { impulse, alignment, latest, prior };
}

/** A COT reading older than this many days is stale (§5.3, §27 Failure 4). */
export const COT_STALE_DAYS = 10;

/** A Treasury reading older than this many calendar days is stale. */
export const TREASURY_STALE_DAYS = 5;

/** Age in days of an ISO `YYYY-MM-DD` date against now. */
export function ageInDays(isoDate: string, now: number = Date.now()): number {
  return (now - new Date(isoDate + 'T00:00:00Z').getTime()) / 86400000;
}

/**
 * Reduces a timestamp to its calendar date.
 *
 * CFTC's Socrata API returns `calendar_date` columns as
 * `2026-09-29T00:00:00.000`. Passing that to a date-only consumer risks a local
 * timezone shift moving it to the previous day, so the timestamp part is
 * stripped rather than parsed.
 */
export function dateOnly(timestamp: string): string | null {
  const m = /^(\d{4}-\d{2}-\d{2})/.exec(timestamp.trim());
  if (!m) return null;
  return Number.isNaN(new Date(m[1] + 'T00:00:00Z').getTime()) ? null : m[1];
}

/** Parses a CSV line that may contain quoted fields. */
export function splitCsv(line: string): string[] {
  const out: string[] = [];
  let cur = '';
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++; } else quoted = false;
      } else cur += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { out.push(cur); cur = ''; }
    else cur += ch;
  }
  out.push(cur);
  return out;
}

/** Numeric field reader: blank and NA both mean "not reported", never zero. */
export function num(v: string | undefined): number | null {
  if (v === undefined) return null;
  const t = v.trim();
  if (t === '' || t === 'NA') return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}