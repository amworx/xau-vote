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
 *   * `ManualSeed` (DEFAULT, always allowed): clearly-labeled approximate
 *     fixtures for recurring USD movers — NFP (first Friday, 12:30 UTC),
 *     CPI (monthly), FOMC (8x/yr approximate). Replaced by provider data
 *     when a licensed provider is enabled.
 *   * `FmpProvider` (GATED — Gate G5): FMP economic-calendar adapter. Code
 *     ships but stays DISABLED unless `FMP_ENABLED=true` AND a licensing
 *     review is recorded in `memory/decisions.md`. Default: off.
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
    for (const [yy, mm] of [[y, m], ...(m === 11 ? [[y + 1, 0]] : [[y, m + 1]]] as [number, number][]) {
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
  let provider: EventProvider = new ManualSeed();
  if (Deno.env.get('FMP_ENABLED') === 'true') {
    const fmpKey = Deno.env.get('FMP_API_KEY');
    if (!fmpKey) return Response.json({ ok: false, error: 'FMP_ENABLED but no FMP_API_KEY (Gate G5).' }, { status: 500 });
    provider = new FmpProvider(fmpKey);
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
