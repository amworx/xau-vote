/**
 * sentiment-layers — scheduled Edge Function.
 *
 * Measures the slow sentiment layers of
 * `instruction/XAUUSD_IMPLEMENTATION_READY_METHODOLOGY.md` §5 and writes them to
 * `sentiment_layers`, which the app reads.
 *
 * THIS SLICE — two of the four §5.1 layers, chosen because they are public, need
 * no account, and need no API key:
 *
 *   market_implied (20%)  US Treasury daily real yield curve  → real yield impulse
 *   positioning    (25%)  CFTC disaggregated Commitments of Traders → managed money
 *
 * A layer that cannot be measured is reported as unavailable rather than scored
 * 0, because 0 means "neutral" and silence is not neutrality.
 *
 * `gold_fundamentals` is no longer among them: World Gold Council data is
 * licensed for personal, non-commercial use only and needs written authorisation
 * we do not have, so it is removed outright rather than left as a pending null
 * row that pinned macro coverage at 73% forever. D-20261006-011.
 *
 * ── Why the CFTC Socrata API and not cftc.gov ───────────────────────────────
 * `www.cftc.gov` serves its weekly .txt and yearly .zip files through a bot
 * challenge: from Supabase's egress they return HTTP 403 with a "Just a moment"
 * interstitial, and spoofing a browser User-Agent does not clear it (verified
 * 2026-10-05). `publicreporting.cftc.gov` is CFTC's own Socrata API for the same
 * data and answers normally, so this reads through it. It is also the better
 * shape for this job:
 *
 *   - one ~1.5s query instead of ~6.5MB of yearly archives
 *   - the full 156-week window §1.6 asks for, because the API reaches further
 *     back than three calendar years of zips (which yielded only 144 weeks, as
 *     the running year is always partial)
 *   - columns selected by name, so a CFTC schema change cannot silently shift a
 *     value into the wrong field
 *
 * Both datasets were cross-checked on 2026-10-05: the Socrata row for
 * 2026-09-29 (open interest 406456, managed money 131711 / 11393) matches the
 * weekly .txt byte for byte.
 *
 * Dataset: 72hh-3qpy "Disaggregated - Futures Only". The sibling 6dca/kh3c-gbw2
 * "Combined" folds options in, which §1.6 does not ask for, and the similarly
 * named ubmb-6exi has been frozen since 2022.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  WEIGHTS,
  HORIZONS,
  GOLD_CODE,
  PERCENTILE_WEEKS,
  COT_STALE_DAYS,
  TREASURY_STALE_DAYS,
  cotScore,
  percentileRank,
  alignmentOf,
  parseTreasuryDate,
  realYieldImpulse,
  ageInDays,
  splitCsv,
  num,
  dateOnly,
  type TreasuryRow,
} from '../_shared/sentiment.ts';
import {
  POLICY_WEIGHT,
  POLICY_STALE_DAYS,
  policyScoreFor,
  policyDecay,
  parseFomcStatement,
  latestStatementPaths,
  targetChangeBp,
  type FomcStatement,
} from '../_shared/policy.ts';

const COT_DATASET = '72hh-3qpy'; // Disaggregated - Futures Only
const COT_API = `https://publicreporting.cftc.gov/resource/${COT_DATASET}.json`;

const TREASURY_CSV =
  'https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv';

const FOMC_CALENDAR = 'https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm';

interface CotRow {
  date: string;
  openInterest: number;
  mmLong: number;
  mmShort: number;
  managedNet: number;
}

async function getJson(url: string): Promise<unknown> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} for ${url}`);
  return await res.json();
}

async function getText(url: string): Promise<string> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} for ${url}`);
  return await res.text();
}

/**
 * §1.6: managed money long/short, open interest, and the 156-week history in a
 * single request — newest first, so index 0 is the current reading and the
 * remainder is the percentile window.
 *
 * Only the four needed columns are requested. Asking for `$order` DESC with
 * `$limit` matters: an ascending limit would return the OLDEST rows in the
 * table and silently rank the current reading against stale history.
 */
async function readCotSeries(): Promise<CotRow[]> {
  const select = [
    'report_date_as_yyyy_mm_dd',
    'open_interest_all',
    'm_money_positions_long_all',
    'm_money_positions_short_all',
  ].join(',');
  const url =
    `${COT_API}?$select=${encodeURIComponent(select)}` +
    `&$where=${encodeURIComponent(`cftc_contract_market_code='${GOLD_CODE}'`)}` +
    `&$order=${encodeURIComponent('report_date_as_yyyy_mm_dd DESC')}` +
    `&$limit=${PERCENTILE_WEEKS}`;

  const raw = await getJson(url);
  if (!Array.isArray(raw)) throw new Error('CFTC API did not return an array');
  const rows: CotRow[] = [];
  for (const r of raw as Record<string, unknown>[]) {
    const date = dateOnly(String(r.report_date_as_yyyy_mm_dd ?? ''));
    const oi = Number(r.open_interest_all);
    const mmLong = Number(r.m_money_positions_long_all);
    const mmShort = Number(r.m_money_positions_short_all);
    // A week with a missing field is dropped rather than treated as zero
    // positioning — a gap in the record is not a reading.
    if (date === null || !Number.isFinite(oi) || !Number.isFinite(mmLong) || !Number.isFinite(mmShort)) {
      continue;
    }
    rows.push({ date, openInterest: oi, mmLong, mmShort, managedNet: mmLong - mmShort });
  }
  if (rows.length === 0) throw new Error('no usable COMEX gold rows from CFTC');
  return rows;
}

/**
 * §5.1 market-implied: the Treasury daily real yield curve, as UTC-dated rows.
 *
 * home.treasury.gov costs ~18s per request from Supabase's egress regardless of
 * size (measured 2026-10-05: an 6.8KB CSV took 18.3s), so the current year is
 * fetched alone and the prior year is only requested if that leaves too few
 * rows to compare — which happens in the first days of January. Fetching both
 * unconditionally doubled a 19s run to 37s for data that is almost never used.
 * FRED carries the same series (DFII5/DFII10) but did not respond at all when
 * tried, so it is not a usable fallback.
 */
async function readTreasury(): Promise<TreasuryRow[]> {
  const year = new Date().getUTCFullYear();

  const fetchYear = async (y: number): Promise<TreasuryRow[]> => {
    const url =
      `${TREASURY_CSV}/${y}/all?type=daily_treasury_real_yield_curve` +
      `&field_tdr_date_value=${y}&page&_format=csv`;
    const lines = (await getText(url)).split(/\r?\n/);
    const header = splitCsv(lines[0] ?? '').map((h) => h.trim());
    const iDate = header.indexOf('Date');
    const i5 = header.indexOf('5 YR');
    const i10 = header.indexOf('10 YR');
    if (iDate < 0) return [];
    const out: TreasuryRow[] = [];
    for (let i = 1; i < lines.length; i++) {
      const f = splitCsv(lines[i]);
      const date = parseTreasuryDate(f[iDate] ?? '');
      if (date === null) continue;
      out.push({ date, real5y: num(f[i5]), real10y: num(f[i10]) });
    }
    return out;
  };

  const rows = await fetchYear(year);
  // realYieldImpulse needs six usable observations; ask for the previous year
  // only when the current one cannot supply them.
  const usable = rows.filter((r) => r.real10y !== null).length;
  if (usable < 6) {
    const prior = await fetchYear(year - 1);
    rows.push(...prior);
  }
  rows.sort((a, b) => a.date.localeCompare(b.date));
  return rows;
}

type Row = Record<string, unknown>;

/**
 * §5.2 policy layer: the latest FOMC statement plus the one before it.
 *
 * Two statements, because §5.2 wants the target-rate *change* and the SEP
 * comparison; the previous statement supplies the baseline the change is
 * measured against. The calendar page carries every statement link with the date
 * in the URL, so "latest" needs no calendar parsing.
 */
async function readPolicy(): Promise<{
  current: FomcStatement;
  previous: FomcStatement | null;
  currentDate: string;
  previousDate: string | null;
  currentUrl: string;
}> {
  const calendarHtml = await getText(FOMC_CALENDAR);
  const statements = latestStatementPaths(calendarHtml, 2);
  if (statements.length === 0) throw new Error('no FOMC statement links on the calendar');

  const [latest, prior] = statements;
  const currentHtml = await getText(`https://www.federalreserve.gov${latest.url}.htm`);
  const current = parseFomcStatement(currentHtml, latest.date);

  let previous: FomcStatement | null = null;
  let previousDate: string | null = null;
  if (prior) {
    try {
      const previousHtml = await getText(`https://www.federalreserve.gov${prior.url}.htm`);
      previous = parseFomcStatement(previousHtml, prior.date);
      previousDate = prior.date;
    } catch {
      // The change against the prior statement is then unmeasured; the current
      // decision verb still stands on its own.
      previous = null;
    }
  }

  return {
    current,
    previous,
    currentDate: latest.date,
    previousDate,
    currentUrl: `https://www.federalreserve.gov${latest.url}.htm`,
  };
}

Deno.serve(async () => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(url, key);
  const notes: string[] = [];
  const layers: Row[] = [];

  // ── market_implied (20%) ───────────────────────────────────────────────────
  try {
    const { impulse, alignment, latest } = realYieldImpulse(await readTreasury());
    if (!latest) throw new Error('no Treasury rows');
    layers.push({
      layer: 'market_implied',
      horizon: HORIZONS.market_implied,
      weight: WEIGHTS.market_implied,
      // §5 defines no raw score for this layer; alignment is the unit the
      // confluence engine consumes.
      score: null,
      alignment,
      measured_at: latest.date + 'T00:00:00Z',
      source: 'US Treasury daily real yield curve',
      source_url:
        'https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?type=daily_treasury_real_yield_curve',
      stale: ageInDays(latest.date) > TREASURY_STALE_DAYS,
      detail: {
        real10y: latest.real10y,
        real5y: latest.real5y,
        change5d_bp: impulse,
        as_of: latest.date,
      },
    });
  } catch (e) {
    notes.push(`market_implied unavailable: ${(e as Error).message}`);
  }

  // ── positioning (25%) ──────────────────────────────────────────────────────
  try {
    const series = await readCotSeries();
    const current = series[0];
    // The current reading ranks against the rest of the window. Including the
    // current value in its own reference set is what §1.6's percentile_rank
    // specifies, so it stays in.
    const window = series.slice(0, PERCENTILE_WEEKS);
    const percentile =
      Math.round(percentileRank(window.map((r) => r.managedNet), current.managedNet) * 10) / 10;
    const score = cotScore(percentile);
    layers.push({
      layer: 'positioning',
      horizon: HORIZONS.positioning,
      weight: WEIGHTS.positioning,
      score,
      alignment: alignmentOf(score),
      measured_at: current.date + 'T00:00:00Z',
      source: 'CFTC disaggregated Commitments of Traders, COMEX gold (088691)',
      source_url: 'https://publicreporting.cftc.gov/resource/72hh-3qpy.json',
      stale: ageInDays(current.date) > COT_STALE_DAYS,
      detail: {
        managed_net_contracts: current.managedNet,
        managed_money_long: current.mmLong,
        managed_money_short: current.mmShort,
        managed_net_percent_of_oi:
          current.openInterest === 0 ? null : Math.round((current.managedNet / current.openInterest) * 10000) / 10000,
        open_interest: current.openInterest,
        percentile_156w: percentile,
        sample_weeks: window.length,
        // The oldest week actually used, so the reader can see the real span.
        history_start: window[window.length - 1].date,
        as_of: current.date,
        // §5.3: an extreme reading without a price-trend leg is not scored ±2,
        // and divergence is undefined rather than asserted.
        trend_confirmed: false,
        positioning_divergence: null,
      },
    });
  } catch (e) {
    notes.push(`positioning unavailable: ${(e as Error).message}`);
  }

  // ── policy (35%) ───────────────────────────────────────────────────────
  // The largest single weight in the §5.1 vote, and previously a null
  // placeholder that also dragged macro coverage down to 27%.
  try {
    const { current, previous, currentDate, previousDate, currentUrl } = await readPolicy();
    const raw = policyScoreFor(current.action);
    const days = ageInDays(currentDate);
    const effective = policyDecay(raw, days);
    // The decayed score drives direction; the raw magnitude is kept so the UI
    // can say "a hike, now 19 days old" instead of only "-1.06".
    layers.push({
      layer: 'policy',
      horizon: HORIZONS.policy,
      weight: POLICY_WEIGHT,
      score: effective,
      alignment: alignmentOf(Math.round(effective)),
      measured_at: currentDate + 'T00:00:00Z',
      source: 'Federal Reserve FOMC statement',
      source_url: currentUrl,
      stale: days > POLICY_STALE_DAYS,
      detail: {
        action: current.action,
        raw_score: raw,
        effective_score: effective,
        decay_days: Math.round(days),
        // A negative effective score leans bearish for gold, which is support
        // for a short and a conflict for a long. The confluence engine resolves
        // that side-awareness; this layer only reports direction.
        target_low_pct: current.targetLow,
        target_high_pct: current.targetHigh,
        target_change_bp: previous ? targetChangeBp(previous, current) : null,
        previous_statement_date: previousDate,
        previous_action: previous?.action ?? null,
        dissents: current.dissents,
        // §5.2 items 4-7 want the SEP median path compared with the previous SEP.
        // The Fed publishes the projections only as PDF, which this runtime
        // cannot read, and FRED did not respond when tried. Recorded as
        // unmeasured rather than inferred from the target rate.
        sep_projection: null,
        sep_reason: 'Fed publishes SEP projections as PDF only; not parsed',
        decision_sentence: current.decisionSentence,
      },
    });
  } catch (e) {
    notes.push(`policy unavailable: ${(e as Error).message}`);
  }

  // ── gold_fundamentals: REMOVED, not pending ────────────────────────────────
  // This used to be written as an explicit null row so the app could tell "this
  // layer does not exist yet" from "this layer exists and reads zero". That was
  // the wrong distinction to draw: the layer is not "not built yet", it is
  // unobtainable. World Gold Council data is licensed for personal,
  // non-commercial use only and needs written authorisation we do not have.
  //
  // Keeping a null row also pinned macro-side coverage at 55/75 = 73% forever,
  // which reads as permanent incompleteness rather than an honest statement of
  // what is measurable. See D-20261006-011.
  //
  // The existing row is deleted here so the app cannot keep rendering a layer
  // the product has decided not to claim.
  const { error: purgeError } = await db
    .from('sentiment_layers')
    .delete()
    .eq('layer', 'gold_fundamentals');
  if (purgeError) notes.push(`purge gold_fundamentals: ${purgeError.message}`);
  else notes.push('gold_fundamentals removed (unlicensed source)');

  for (const row of layers) {
    const { error } = await db.from('sentiment_layers').upsert(row, { onConflict: 'layer' });
    if (error) notes.push(`write ${row.layer}: ${error.message}`);
    else notes.push(`${row.layer} written`);
  }

  return Response.json({
    ok: !notes.some((n) => n.includes('unavailable') || n.includes('write ')),
    notes,
    now: new Date().toISOString(),
  });
});