/**
 * bls-actuals - issuer numeric actuals for the marquee USD releases.
 *
 * THE GAP: the calendar provider prints actuals as descriptive text with a
 * multi-week lag (verified 2026-10-07: 30-Sep releases still null, mid-August
 * populated). fetch-events keeps that wording verbatim in `actual_text`, but
 * a tradable Results tab wants numbers. The U.S. Bureau of Labor Statistics
 * runs a free public API (api.bls.gov, no key, US public-domain data) that
 * carries the issue figures within days of release, so this job backfills
 * the three releases that move gold most:
 *
 *   CPI report            -> CUUR0000SA0  (CPI-U, all items index, monthly)
 *   Employment Situation  -> CES0000000001 (total nonfarm payrolls, thousands, monthly)
 *   Unemployment Rate     -> LNS14000000  (unemployment rate %, monthly)
 *
 * VINTAGE RULE: BLS monthly points are reference-month values, newest first.
 * A release on calendar date D reports the newest point with reference month
 * strictly before D's month (September CPI released mid-October is the M09
 * point). Annual-average points (period M13) are never a release figure and
 * are skipped. The rule keys off the event date, never the title's month
 * wording — a mislabeled title still scores the right vintage, and a changed
 * release schedule degrades to "no point found" (row left unscored) rather
 * than a wrong figure.
 *
 * SCOPE GUARDS:
 * - Only rows with actual IS NULL are touched. A publisher numeric or an
 *   earlier BLS figure is never overwritten — the issuer is authoritative,
 *   but first-write-wins within this job keeps reruns idempotent.
 * - Only past events (starts_at < now). A future row is a schedule, not a result.
 * - One batched BLS request for all distinct series (keyless quota is
 *   25/day); any HTTP or shape failure throws LOUD so the miss is visible.
 * - PPI, retail sales, GDP, jobless claims have no mapped series yet. Those
 *   rows keep the provider's wording via actual_text — never a BLS number
 *   from the wrong release.
 */

import { createClient } from 'jsr:@supabase/supabase-js@2';

const BLS_URL = 'https://api.bls.gov/publicAPI/v2/timeseries/data/';

/** Title keyword -> BLS series. Payroll keywords win over the bare rate: an
 *  "Employment Situation (Non-Farm Payrolls)" row is the payrolls figure. */
function seriesFor(title: string): string | null {
  const t = title.toLowerCase();
  if (t.includes('non-farm') || t.includes('nonfarm') || t.includes('payroll')) {
    return 'CES0000000001';
  }
  if (t.includes('unemployment rate')) return 'LNS14000000';
  if (t.includes('cpi')) return 'CUUR0000SA0';
  return null;
}

interface BlsPoint {
  year: number;
  month: number; // 1-12; M13 (annual average) excluded at parse
  value: number;
}

/** Newest-first BLS data array -> vintage-correct point for an event date. */
export function vintageFor(
  data: Array<{ year: string; period: string; value: string }>,
  eventDate: Date,
): BlsPoint | null {
  const ey = eventDate.getUTCFullYear();
  const em = eventDate.getUTCMonth() + 1;
  for (const d of data) {
    const m = /^M(\d{2})$/.exec(d.period);
    if (!m) continue;
    const month = parseInt(m[1], 10);
    if (month < 1 || month > 12) continue; // M13 annual average is not a release
    const year = parseInt(d.year, 10);
    if (!Number.isFinite(year)) continue;
    if (year < ey || (year === ey && month < em)) {
      const value = parseFloat(d.value);
      if (!Number.isFinite(value)) continue;
      return { year, month, value };
    }
  }
  return null;
}

Deno.serve(async (_req) => {
  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  const now = new Date();

  const { data: rows, error } = await db
    .from('economic_events')
    .select('id,title,starts_at')
    .eq('currency', 'USD')
    .is('actual', null)
    .lt('starts_at', now.toISOString())
    .order('starts_at', { ascending: false })
    .limit(60);
  if (error) throw new Error(`select unscored: ${error.message}`);

  const targets: Array<{ id: string; title: string; at: Date; series: string }> = [];
  for (const r of rows ?? []) {
    const series = seriesFor(String((r as Record<string, unknown>)['title'] ?? ''));
    if (!series) continue;
    targets.push({
      id: String((r as Record<string, unknown>)['id']),
      title: String((r as Record<string, unknown>)['title']),
      at: new Date(String((r as Record<string, unknown>)['starts_at'])),
      series,
    });
  }
  if (targets.length === 0) {
    console.log('bls-actuals: no mappable unscored releases');
    return Response.json({ ok: true, scored: 0 });
  }

  const seriesIds = [...new Set(targets.map((t) => t.series))];
  const years = targets.map((t) => t.at.getUTCFullYear());
  const startYear = Math.min(...years) - 1;
  const endYear = Math.max(...years);
  const br = await fetch(BLS_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ seriesid: seriesIds, startyear: String(startYear), endyear: String(endYear) }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!br.ok) throw new Error(`BLS HTTP ${br.status}`);
  const body = (await br.json()) as {
    status: string;
    message?: string[];
    Results?: { series?: Array<{ seriesID: string; data: Array<{ year: string; period: string; value: string }> }> };
  };
  if (body.status !== 'REQUEST_SUCCEEDED') {
    throw new Error(`BLS rejected: ${(body.message ?? []).join(' ')}`);
  }
  const bySeries = new Map(
    (body.Results?.series ?? []).map((s) => [s.seriesID, s.data ?? []]),
  );

  let scored = 0;
  const skipped: string[] = [];
  for (const t of targets) {
    const point = vintageFor(bySeries.get(t.series) ?? [], t.at);
    if (!point) {
      skipped.push(t.title);
      continue;
    }
    const { error: uerr } = await db
      .from('economic_events')
      .update({
        actual: point.value,
        actual_source: `BLS ${t.series} (public domain, ref ${point.year}-M${String(point.month).padStart(2, '0')})`,
      })
      .eq('id', t.id)
      .is('actual', null); // first-write-wins: never fight a concurrent scorer
    if (uerr) throw new Error(`update ${t.id}: ${uerr.message}`);
    scored++;
  }
  console.log(`bls-actuals: scored=${scored} skipped=${skipped.length}`);
  return Response.json({ ok: true, scored, skipped });
});
