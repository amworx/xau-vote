/**
 * calendar-crosscheck - daily Finance Calendar vs l3vlup validation (D-20261007-022,
 * directive step 8: official-source validation).
 *
 * WHAT IT DOES
 *
 * Compares our Finance Calendar HIGH USD rows against the l3vlup calendar,
 * which is built straight from official schedules (BLS release calendar, BEA,
 * Fed FOMC calendar). Every finding lands in `calendar_discrepancies` as a
 * QUESTION for manual issuer check - never an auto-correction. A third
 * party's error must not flap the blackout guard, and our own provider's
 * error must not hide behind a validator's silence either: both directions
 * are reported (MISSING_IN_FC and MISSING_IN_L3VLUP).
 *
 * MATCHING
 *
 * By keyword sets, not string equality: "US CPI Report October 2026" and
 * "Consumer Price Index" are the same release in different house styles.
 * Anything unmatched on either side is reported as missing rather than
 * force-matched - a wrong match that agrees is worse than an honest gap.
 *
 * TIMES
 *
 * l3vlup times are ET wall-clock. Converted with US DST rules (second Sunday
 * of March to first Sunday of November; EDT=UTC-4 inside, EST=UTC-5
 * outside). A mismatch counts only past 60 minutes of difference, so DST
 * edge wobble and minute-level scheduling noise do not page anyone.
 *
 * DEDUPE
 *
 * Already-OPEN rows for the same (kind, event) suppress re-inserts. A finding
 * stays OPEN until a human confirms or dismisses it; the job must not stack
 * eleven copies of the same question.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';

const L3VLUP_CALENDAR_URL =
  'https://raw.githubusercontent.com/Surojitc/l3vlup-skills/main/data/calendar.auto.json';

/** Release keywords. First matching set wins; order is longest-first. */
const KEYWORDS: string[][] = [
  ['non-farm', 'nfp', 'employment situation', 'payroll'],
  ['consumer price', 'cpi'],
  ['producer price', 'ppi'],
  ['personal income', 'outlays', 'pce'],
  ['gross domestic', 'gdp'],
  ['retail sales'],
  ['ism manufacturing'],
  ['ism services'],
  ['jolts', 'job openings', 'labor turnover', 'labour turnover'],
  ['jobless', 'jobless claims', 'initial claims'],
  ['fomc'],
  ['beige book'],
  ['trade balance', 'trade deficit', 'international trade', 'import and export'],
  ['home sales', 'existing home', 'new home'],
  ['industrial production'],
  ['consumer confidence', 'consumer sentiment'],
  ['durable goods'],
  ['housing starts', 'new residential construction'],
];

function keyOf(title: string): string | null {
  const t = title.toLowerCase();
  for (const set of KEYWORDS) {
    if (set.some((k) => t.includes(k))) return set[0];
  }
  return null;
}

/** US DST: second Sunday of March through first Sunday of November. */
function isUsDst(d: Date): boolean {
  const y = d.getUTCFullYear();
  const nthSunday = (month: number, n: number): Date => {
    const first = new Date(Date.UTC(y, month, 1));
    const add = (7 - first.getUTCDay()) % 7;
    return new Date(Date.UTC(y, month, 1 + add + (n - 1) * 7));
  };
  // Transition instants in UTC: 2nd Sun Mar 07:00, 1st Sun Nov 06:00.
  const start = nthSunday(2, 2);
  start.setUTCHours(7, 0, 0, 0);
  const end = nthSunday(10, 1);
  end.setUTCHours(6, 0, 0, 0);
  return d.getTime() >= start.getTime() && d.getTime() < end.getTime();
}

/** "2026-10-14" + "08:30" ET -> UTC ISO. Null when unparseable. */
function etToUtc(date: string, time: string | null): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const m = /^(\d{1,2}):(\d{2})$/.exec(time ?? '');
  if (!m) return null;
  const guess = new Date(`${date}T${m[1].padStart(2, '0')}:${m[2]}:00Z`);
  if (Number.isNaN(guess.getTime())) return null;
  const offsetHrs = isUsDst(guess) ? 4 : 5;
  return new Date(guess.getTime() + offsetHrs * 3600 * 1000).toISOString();
}

const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });

interface FcRow {
  external_id: string;
  title: string;
  starts_at: string;
}

Deno.serve(async () => {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    return json({ ok: false, error: 'missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY' }, 500);
  }
  const db = createClient(url, key);
  const now = new Date();

  // 1. Our side: Finance Calendar USD rows, yesterday through +14d.
  // Yesterday included so a just-passed release still gets its check. All
  // impacts are fetched: presence is matched across impact scales (Finance
  // Calendar calls PPI medium where the validator says high), because an
  // impact-scale difference is provider judgment, not a factual discrepancy.
  // Only HIGH rows are validated outbound; the rest exist so inbound matches
  // do not false-flag.
  const { data: fcRows, error: fcErr } = await db
    .from('economic_events')
    .select('external_id,title,starts_at,impact')
    .eq('provider', 'finance-calendar')
    .eq('currency', 'USD')
    .gte('starts_at', new Date(now.getTime() - 24 * 3600 * 1000).toISOString())
    .lte('starts_at', new Date(now.getTime() + 14 * 24 * 3600 * 1000).toISOString())
    .order('starts_at', { ascending: true });
  if (fcErr) return json({ ok: false, error: `fc read failed: ${fcErr.message}` }, 500);
  const fcHigh = ((fcRows ?? []) as Array<FcRow & { impact?: unknown }>).filter(
    (r) => r.impact === 'HIGH',
  );

  // 2. Validator side: l3vlup calendar file.
  let l3: { events?: unknown };
  try {
    const r = await fetch(L3VLUP_CALENDAR_URL, {
      headers: { accept: 'application/json' },
      signal: AbortSignal.timeout(25_000),
    });
    if (!r.ok) throw new Error(`l3vlup HTTP ${r.status}`);
    l3 = (await r.json()) as { events?: unknown };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`calendar-crosscheck: l3vlup fetch failed: ${msg}`);
    return json({ ok: false, error: `l3vlup fetch failed: ${msg}` }, 500);
  }
  if (!Array.isArray(l3.events)) {
    return json({ ok: false, error: 'unexpected l3vlup shape' }, 500);
  }
  interface L3Event {
    date?: unknown;
    time?: unknown;
    tz?: unknown;
    country?: unknown;
    title?: unknown;
    importance?: unknown;
  }
  const l3HighUs = (l3.events as L3Event[]).filter(
    (e) => e.country === 'US' && e.importance === 'high',
  );

  // 3. Already-open findings, for dedupe.
  const { data: openRows } = await db
    .from('calendar_discrepancies')
    .select('kind,fc_external_id,l3vlup_title,l3vlup_date')
    .eq('status', 'OPEN');
  const openKeys = new Set(
    ((openRows ?? []) as Array<Record<string, unknown>>).map((r) =>
      `${r['kind']}|${r['fc_external_id'] ?? ''}|${r['l3vlup_title'] ?? ''}|${r['l3vlup_date'] ?? ''}`
    ),
  );

  const findings: Array<Record<string, unknown>> = [];
  const seenL3 = new Set<L3Event>();

  // All US validator events at any importance: presence-matching is
  // impact-blind (see section 1). The HIGH filter below selects WHAT gets
  // validated, never what it can match against.
  const l3AllUs = (l3.events as L3Event[]).filter((e) => e.country === 'US');

  // 4a. Every FC HIGH USD event needs an official-schedule counterpart.
  for (const fc of fcHigh) {
    const k = keyOf(fc.title);
    const match = k === null
      ? null
      : l3AllUs.find((e) => typeof e.title === 'string' && keyOf(e.title) === k);
    if (k === null || !match) {
      findings.push({
        kind: k === null ? 'UNMATCHABLE_TITLE' : 'MISSING_IN_L3VLUP',
        fc_external_id: fc.external_id,
        fc_title: fc.title,
        fc_starts_at: fc.starts_at,
        l3vlup_title: null,
        l3vlup_date: null,
        l3vlup_time: null,
        detail: k === null
          ? 'No keyword set covers this title; add one or match by hand against the official issuer schedule.'
          : 'Finance Calendar lists a HIGH USD release with no same-release entry in the official-schedule file. Check the issuer page: wrong on our side, or a coverage gap on theirs.',
      });
      continue;
    }
    seenL3.add(match);
    const l3Utc = etToUtc(String(match.date ?? ''), typeof match.time === 'string' ? match.time : null);
    if (l3Utc === null) {
      findings.push({
        kind: 'L3VLUP_UNPARSEABLE_TIME',
        fc_external_id: fc.external_id,
        fc_title: fc.title,
        fc_starts_at: fc.starts_at,
        l3vlup_title: String(match.title ?? ''),
        l3vlup_date: String(match.date ?? ''),
        l3vlup_time: typeof match.time === 'string' ? match.time : null,
        detail: 'Matched by release, but the validator time could not be parsed. Compare by hand.',
      });
      continue;
    }
    const diffMin = Math.abs(new Date(fc.starts_at).getTime() - new Date(l3Utc).getTime()) / 60000;
    if (diffMin > 60) {
      findings.push({
        kind: 'DATETIME_MISMATCH',
        fc_external_id: fc.external_id,
        fc_title: fc.title,
        fc_starts_at: fc.starts_at,
        l3vlup_title: String(match.title ?? ''),
        l3vlup_date: String(match.date ?? ''),
        l3vlup_time: typeof match.time === 'string' ? match.time : null,
        detail: `Same release, times differ by ${Math.round(diffMin)} minutes (FC ${fc.starts_at} vs official-schedule ${l3Utc}). Check the issuer page; official wins.`,
      });
    }
  }

  // 4b. Every l3vlup HIGH US event needs an FC counterpart. (Same keyword
  // match in reverse; an official-schedule release Finance Calendar missed is
  // a coverage gap on our side.)
  //
  // Windowed to our own fetch range (yesterday through +14d). The validator
  // file spans months ahead; anything past our window is absence of data, not
  // absence of coverage, and flagging it would page a human about November
  // while October burns.
  const windowStart = now.getTime() - 24 * 3600 * 1000;
  const windowEnd = now.getTime() + 14 * 24 * 3600 * 1000;
  for (const e of l3HighUs) {
    if (seenL3.has(e) || typeof e.title !== 'string') continue;
    if (typeof e.date !== 'string') continue;
    const day = Date.parse(`${e.date}T12:00:00Z`);
    if (Number.isNaN(day) || day < windowStart || day > windowEnd) continue;
    const k = keyOf(e.title);
    const fcHit = k === null
      ? null
      : ((fcRows ?? []) as FcRow[]).find((f) => keyOf(f.title) === k);
    if (!fcHit) {
      findings.push({
        kind: 'MISSING_IN_FC',
        fc_external_id: null,
        fc_title: null,
        fc_starts_at: null,
        l3vlup_title: e.title,
        l3vlup_date: typeof e.date === 'string' ? e.date : null,
        l3vlup_time: typeof e.time === 'string' ? e.time : null,
        detail: 'Official-schedule HIGH US release with no Finance Calendar counterpart in our window. If the issuer confirms it, our calendar has a coverage gap (and the guard is blind to it).',
      });
    }
  }

  // 5. Insert new findings only.
  let inserted = 0;
  let duplicates = 0;
  for (const f of findings) {
    const dedupeKey = `${f['kind']}|${(f['fc_external_id'] as string) ?? ''}|${(f['l3vlup_title'] as string) ?? ''}|${(f['l3vlup_date'] as string) ?? ''}`;
    if (openKeys.has(dedupeKey)) { duplicates++; continue; }
    const { error } = await db.from('calendar_discrepancies').insert({
      kind: f['kind'],
      fc_external_id: f['fc_external_id'],
      fc_title: f['fc_title'],
      fc_starts_at: f['fc_starts_at'],
      l3vlup_title: f['l3vlup_title'],
      l3vlup_date: f['l3vlup_date'],
      l3vlup_time: f['l3vlup_time'],
      detail: f['detail'],
    });
    if (error) {
      console.error(`calendar-crosscheck: insert failed: ${error.message}`);
      return json({ ok: false, error: `insert failed: ${error.message}` }, 500);
    }
    inserted++;
  }

  return json({
    ok: true,
    at: now.toISOString(),
    fc_high_usd: fcHigh.length,
    l3vlup_high_us: l3HighUs.length,
    findings: findings.length,
    inserted,
    duplicates,
  });
});