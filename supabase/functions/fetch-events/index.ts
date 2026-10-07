/**
 * fetch-events — scheduled Edge Function, hourly + on boot (TASK-07 T7.2).
 *
 * Fetches the 7-day USD (+majors) economic calendar through an
 * `EventProvider`, normalizes rows into `economic_events`, and computes
 * surprise flags when actuals are present (NFP ±50K, CPI ±0.2pp, default
 * ±10% of |forecast|). Surprise is volatility context only — it never
 * votes (AGENTS.md rule 9).
 *
 * Providers:
 *   * `FinanceCalendarProvider` (APPROVED, D-20261006-020): Finance Calendar
 *     economic calendar. Free for any use with attribution, no key, no rate
 *     limits. The default production provider.
 *   * `FmpProvider` (GATED — Gate G5): FMP economic-calendar adapter. Code
 *     ships but stays DISABLED unless `FMP_ENABLED=true` AND a licensing
 *     review is recorded in `memory/decisions.md`. Default: off.
 *   * `ManualSeed`: RETIRED from the production path. It computed approximate
 *     NFP/CPI/FOMC dates, and because those rows were indistinguishable from
 *     provider rows once in `economic_events`, the app presented invented
 *     release dates as a real calendar — most visibly a release "six days away"
 *     that no publisher had issued. The class stays so its date arithmetic
 *     remains tested, but nothing can reach it in production.
 *
 * With Finance Calendar approved there is always a provider, so the empty
 * calendar now means the provider returned nothing (or failed loudly), not
 * that none is configured. Silence is recoverable; invented dates are not.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
 *      FMP_ENABLED (default 'false'), FMP_API_KEY (only when enabled)
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';

/** Normalized calendar row, provider-agnostic. */
export interface RawEvent {
  externalId: string;
  title: string;
  currency: string;
  impact: 'HIGH' | 'MEDIUM' | 'LOW';
  startsAt: string; // ISO
  forecast: number | null;
  previous: number | null;
  actual: number | null;
  url: string | null;
}

/** Provider contract — never hard-wire a calendar source (rule 8). */
export interface EventProvider {
  readonly name: string;
  fetchUpcoming(now: Date): Promise<RawEvent[]>;
}

/** First Friday of (year, month) at 12:30 UTC — the NFP slot. */
function nfpDate(year: number, month: number): Date {
  const d = new Date(Date.UTC(year, month, 1, 12, 30, 0));
  const shift = (5 - d.getUTCDay() + 7) % 7; // 5 = Friday
  d.setUTCDate(1 + shift);
  return d;
}

/**
 * ManualSeed — approximate fixtures for recurring USD high-impact events.
 * Every row is clearly labeled approximate (title suffix) and carries a
 * stable external_id so provider rows upsert over it 1:1 when enabled.
 */
export class ManualSeed implements EventProvider {
  readonly name = 'manual';

  async fetchUpcoming(now: Date): Promise<RawEvent[]> {
    const out: RawEvent[] = [];
    const y = now.getUTCFullYear();
    const m = now.getUTCMonth();
    // NFP: first Friday of this + next month (covers the 7-day window
    // whenever it falls due, plus the next print for the Upcoming list).
    const months: [number, number][] = m === 11 ? [[y, 11], [y + 1, 0]] : [[y, m], [y, m + 1]];
    for (const [yy, mm] of months) {
      const d = nfpDate(yy, mm);
      out.push({
        externalId: `manual-nfp-${yy}-${String(mm + 1).padStart(2, '0')}`,
        title: 'Non-Farm Payrolls (approx. fixture)',
        currency: 'USD',
        impact: 'HIGH',
        startsAt: d.toISOString(),
        forecast: null,
        previous: null,
        actual: null,
        url: null,
      });
    }
    // CPI: monthly, ~12th 12:30 UTC (approx. fixture).
    for (const off of [0, 1]) {
      const dd = new Date(Date.UTC(y, m + off, 12, 12, 30, 0));
      out.push({
        externalId: `manual-cpi-${dd.getUTCFullYear()}-${String(dd.getUTCMonth() + 1).padStart(2, '0')}`,
        title: 'CPI m/m (approx. fixture)',
        currency: 'USD',
        impact: 'HIGH',
        startsAt: dd.toISOString(),
        forecast: null,
        previous: null,
        actual: null,
        url: null,
      });
    }
    // FOMC: 8x/yr approximate Wednesdays 18:00 UTC (clearly labeled).
    const fomcMonths = [0, 2, 4, 5, 6, 8, 10, 11];
    for (const mm of fomcMonths) {
      const d = new Date(Date.UTC(y, mm, 18, 18, 0, 0));
      // Nudge to Wednesday.
      d.setUTCDate(18 + ((3 - d.getUTCDay() + 7) % 7));
      if (d.getTime() < now.getTime() - 24 * 3600 * 1000) continue;
      out.push({
        externalId: `manual-fomc-${y}-${String(mm + 1).padStart(2, '0')}`,
        title: 'FOMC decision (approx. fixture)',
        currency: 'USD',
        impact: 'HIGH',
        startsAt: d.toISOString(),
        forecast: null,
        previous: null,
        actual: null,
        url: null,
      });
    }
    return out;
  }
}

/**
 * FinanceCalendarProvider — Finance Calendar economic calendar (D-20261006-020).
 *
 * THE approved convenience layer: free for any use with attribution, no key,
 * no rate limits (edge-cached 5 min), CORS open. Polled for an 8-day window;
 * provider docs ask clients to cache since data changes at most hourly, and
 * the hourly cron is that cache.
 *
 * Honest limits, from the live payload shape (verified 2026-10-06):
 * - NO currency field. Derived from title prefixes for the majors; anything
 *   unrecognized is stored as UNKNOWN, never guessed. UNKNOWN rows are hidden
 *   by the app's USD/EUR/GBP chips (fail closed) and never feed the guard as
 *   a US release.
 * - consensus/prior/actual are often STRINGS ("6.4% unemployment") or null.
 *   Only real numbers are stored; anything else stays null so surprise reads
 *   "unavailable" instead of comparing against a parsed-along string.
 * - time_utc can be null (all-day market-hours notices) -> date at 00:00 UTC.
 * - impact strings map explicitly; unrecognized defaults to LOW, which can
 *   never trip the blackout guard.
 */
export class FinanceCalendarProvider implements EventProvider {
  readonly name = 'finance-calendar';

  private static readonly base = 'https://www.financecalendar.com/wp-json/fc/v1';

  /** Ordered: non-US markers first, so "US CPI" never steals "China CPI". */
  private static readonly currencyMarkers: Array<[RegExp, string]> = [
    [/eurozone|europe\b|ecb/i, 'EUR'],
    [/\buk\b|britain|bank of england|gilt/i, 'GBP'],
    [/japan|tokyo|jpx|boj\b/i, 'JPY'],
    [/canada|tsx\b/i, 'CAD'],
    [/australia|rba\b/i, 'AUD'],
    [/china|pboc|caixin/i, 'CNY'],
    [/switz|snb\b/i, 'CHF'],
    [/sweden|riksbank/i, 'SEK'],
    [/norway|norges/i, 'NOK'],
    [/zealand|rbnz\b/i, 'NZD'],
    [/\bUS\b|fed\b|fomc|nfp|payroll|beige book|\bpce\b|ism\b|jolts\b|adp\b/i, 'USD'],
  ];

  static currencyOf(title: string): string {
    for (const [re, ccy] of FinanceCalendarProvider.currencyMarkers) {
      if (re.test(title)) return ccy;
    }
    // Unknown is stored as UNKNOWN, never guessed. The app's currency chips
    // hide it by default (fail closed); inventing USD here would let a foreign
    // release trip the US blackout guard wearing a false flag.
    return 'UNKNOWN';
  }

  async fetchUpcoming(now: Date): Promise<RawEvent[]> {
    // 14-day forward window. The provider covers majors only (no earnings in
    // the API), so depth comes from the window, never from invented rows.
    const from = now.toISOString().slice(0, 10);
    const to = new Date(now.getTime() + 14 * 24 * 3600 * 1000).toISOString().slice(0, 10);
    const r = await fetch(
      `${FinanceCalendarProvider.base}/calendar?from=${from}&to=${to}&limit=500`,
      { headers: { accept: 'application/json' }, signal: AbortSignal.timeout(25_000) },
    );
    if (!r.ok) throw new Error(`Finance Calendar HTTP ${r.status}`);
    const body = (await r.json()) as { events?: unknown };
    if (!Array.isArray(body.events)) throw new Error('unexpected calendar shape');
    return (body.events as Array<Record<string, unknown>>).map((row, i) => {
      const title = typeof row['title'] === 'string' && row['title'].length > 0
        ? row['title']
        : typeof row['name'] === 'string' && row['name'].length > 0
          ? row['name']
          : 'Untitled event';
      const url = typeof row['url'] === 'string' ? row['url'] : null;
      const slug = url?.match(/\/event\/([^/]+)\/?$/)?.[1];
      const date = typeof row['date'] === 'string' ? row['date'] : from;
      const timeUtc = typeof row['time_utc'] === 'string' ? row['time_utc'] : null;
      const startsAt = timeUtc ?? `${date}T00:00:00Z`;
      const impactRaw = String(row['impact'] ?? '').toLowerCase();
      const num = (v: unknown): number | null =>
        typeof v === 'number' && Number.isFinite(v) ? v : null;
      return {
        externalId: `fc-${slug ?? `${date}-${i}`}`,
        title,
        currency: FinanceCalendarProvider.currencyOf(title),
        impact: impactRaw === 'high' ? 'HIGH' : impactRaw === 'medium' ? 'MEDIUM' : 'LOW',
        startsAt: new Date(startsAt).toISOString(),
        forecast: num(row['consensus']),
        previous: num(row['prior']),
        actual: num(row['actual']),
        url,
      };
    });
  }
}

/**
 * FmpProvider — FMP economic-calendar adapter.
 * GATED (Gate G5): constructed but never called unless FMP_ENABLED=true
 * with FMP_API_KEY set and a recorded licensing review.
 */
export class FmpProvider implements EventProvider {
  readonly name = 'fmp';
  constructor(private apiKey: string) {}

  async fetchUpcoming(now: Date): Promise<RawEvent[]> {
    const from = now.toISOString().slice(0, 10);
    const to = new Date(now.getTime() + 7 * 24 * 3600 * 1000).toISOString().slice(0, 10);
    const url =
      `https://financialmodelingprep.com/stable/economic-calendar?from=${from}&to=${to}&apikey=${this.apiKey}`;
    const r = await fetch(url);
    if (!r.ok) throw new Error(`FMP calendar HTTP ${r.status}`);
    const rows = (await r.json()) as Array<Record<string, unknown>>;
    const impactOf = (v: unknown): RawEvent['impact'] => {
      const s = String(v ?? '').toLowerCase();
      if (s.includes('high')) return 'HIGH';
      if (s.includes('medium') || s.includes('moderate')) return 'MEDIUM';
      return 'LOW';
    };
    return rows.map((row, i) => ({
      externalId: `fmp-${String(row['date'] ?? i)}-${String(row['event'] ?? i)}`,
      title: String(row['event'] ?? 'Unknown event'),
      currency: String(row['currency'] ?? 'USD'),
      impact: impactOf(row['impact']),
      startsAt: new Date(String(row['date'])).toISOString(),
      forecast: typeof row['estimate'] === 'number' ? row['estimate'] : null,
      previous: typeof row['previous'] === 'number' ? row['previous'] : null,
      actual: typeof row['actual'] === 'number' ? row['actual'] : null,
      url: null,
    }));
  }
}

/** Per-indicator surprise thresholds (addendum §3.3). */
function surpriseThreshold(title: string, forecast: number | null): number {
  const t = title.toLowerCase();
  if (t.includes('non-farm') || t.includes('nfp') || t.includes('payroll')) return 50; // ±50K
  if (t.startsWith('cpi') || t.includes('cpi')) return 0.2; // ±0.2pp
  if (forecast !== null && forecast !== 0) return Math.abs(forecast) * 0.1;
  return Number.POSITIVE_INFINITY; // no basis → never flag
}

/** 'hot' | 'cold' | 'inline' | null (null = no actuals yet). */
export function surpriseFlag(
  title: string,
  actual: number | null,
  forecast: number | null,
): 'hot' | 'cold' | 'inline' | null {
  if (actual === null || forecast === null) return null;
  const d = actual - forecast;
  const tol = surpriseThreshold(title, forecast);
  if (Math.abs(d) <= tol) return 'inline';
  return d > 0 ? 'hot' : 'cold';
}

Deno.serve(async (_req) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(url, key);
  const now = new Date();

  // Gate G5: FMP stays disabled unless explicitly enabled + reviewed.
  // Finance Calendar is the approved default (D-20261006-020): keyless, so
  // there is no credential to check, only the fetch itself, which fails loudly
  // below. ManualSeed remains unreachable in production by construction - it
  // is never instantiated here.
  let provider: EventProvider;
  if (Deno.env.get('FMP_ENABLED') === 'true') {
    const fmpKey = Deno.env.get('FMP_API_KEY');
    if (!fmpKey) {
      return Response.json(
        { ok: false, error: 'FMP_ENABLED but no FMP_API_KEY (Gate G5).' },
        { status: 500 },
      );
    }
    provider = new FmpProvider(fmpKey);
  } else {
    provider = new FinanceCalendarProvider();
  }

  let rows: RawEvent[];
  try {
    rows = await provider.fetchUpcoming(now);
  } catch (e) {
    return Response.json({ ok: false, error: String(e) }, { status: 500 });
  }

  let upserted = 0;
  for (const e of rows) {
    const { error } = await db.from('economic_events').upsert(
      {
        provider: provider.name,
        external_id: e.externalId,
        title: e.title,
        currency: e.currency,
        impact: e.impact,
        starts_at: e.startsAt,
        actual: e.actual,
        forecast: e.forecast,
        previous: e.previous,
        surprise: surpriseFlag(e.title, e.actual, e.forecast),
        url: e.url,
        collected_at: now.toISOString(),
      },
      { onConflict: 'provider,external_id' },
    );
    if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });
    upserted++;
  }
  console.log(`fetch-events: provider=${provider.name} upserted=${upserted}`);
  return Response.json({ ok: true, provider: provider.name, upserted, at: now.toISOString() });
});
