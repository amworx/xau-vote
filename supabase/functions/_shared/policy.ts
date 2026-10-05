/**
 * FOMC policy parsing and scoring — pure logic, shared by the
 * `sentiment-layers` Edge Function and its tests.
 *
 * Implements `instruction/XAUUSD_IMPLEMENTATION_READY_METHODOLOGY.md` §5.2:
 * collect the latest FOMC statement, record the target-rate change, record
 * voting dissents, and score the policy layer at 35% of the vote.
 *
 * WHY THE STATEMENT TEXT AND NOT A DATA FEED
 * §5.2 says to use "only documented statements and official voting
 * information". The decision sentence of the statement IS the official record,
 * and the Fed serves it as plain HTML. FRED carries the same target rate as a
 * tidy CSV but did not respond when tried (2026-10-05), and the SEP projections
 * are published only as PDF, which this runtime cannot read. Both are recorded
 * below as unmeasured rather than guessed.
 *
 * The 35% weight and the §5.2 score table mean this layer moves verdicts, so
 * every ambiguous case resolves to "neutral/uncertain" (0) instead of a guess.
 */

/** The decision verbs that appear in a statement's "decided to ..." sentence. */
export type FomcAction = 'raise' | 'lower' | 'maintain' | 'unknown';

/** Policy layer weight, §5.1. The single largest of the four. */
export const POLICY_WEIGHT = 35;

/** §5.2 decay constant: score_effective = raw * exp(-days / 30). */
export const POLICY_DECAY_DAYS = 30;

/**
 * A reading older than this is not worth presenting as current policy.
 * Roughly one full decay constant, after which the effective score is under 37%
 * of raw and the decision has certainly been priced.
 */
export const POLICY_STALE_DAYS = 45;

/**
 * §5.2 policy score table, verbatim:
 *
 *   rate_hike_or_higher_path  = -2 gold
 *   unchanged_but_hawkish     = -1 gold
 *   neutral/uncertain         =  0
 *   unchanged_but_dovish      = +1 gold
 *   rate_cut_or_lower_path    = +2 gold
 *
 * The two "unchanged" rows are the hawkish/dovish language bands. Classifying
 * free text as hawkish or dovish is a judgement call, and §5.2's critical rule
 * warns that individual statements are inputs rather than truth. An unchanged
 * decision therefore scores 0 ("neutral/uncertain") and records
 * `unchangedAction: true`, leaving the ±1 nuance explicitly unmeasured. Getting
 * the direction of a rate wrong is far more costly than losing one point of
 * score on an unchanged decision.
 */
export function policyScoreFor(action: FomcAction): number {
  switch (action) {
    case 'raise':
      return -2;
    case 'lower':
      return 2;
    case 'maintain':
      return 0;
    case 'unknown':
      return 0;
  }
}

/** §5.2: policy_score_effective = raw_score * exp(-days_since_event / 30). */
export function policyDecay(raw: number, daysSinceEvent: number): number {
  const days = Math.max(0, daysSinceEvent);
  const factor = Math.exp(-days / POLICY_DECAY_DAYS);
  return Math.round(raw * factor * 100) / 100;
}

/** Removes tags and collapses whitespace so the decision sentence is readable. */
export function stripHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&#8217;|&rsquo;/gi, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Parses one endpoint of a target range.
 *
 * The Fed writes mixed fractions: "3-1/2", "3-3/4", "4-1/4", and whole numbers
 * like "4". "3-3/4" is 3.75, NOT 3 minus 3/4 — the hyphen belongs to the mixed
 * number, so the fraction is only a fraction when it follows a whole part.
 */
export function parsePercentToken(token: string): number | null {
  const m = /^(\d+)(?:-(\d+)\/(\d+))?$/.exec(token.trim());
  if (!m) return null;
  const whole = Number(m[1]);
  if (m[2] === undefined) return whole;
  const den = Number(m[3]);
  if (den === 0) return null;
  return whole + Number(m[2]) / den;
}

/**
 * Extracts the target range from text ending in "percent".
 *
 * Returns null when the shape is not recognised, so the caller can record an
 * unmeasured reading rather than a fabricated 0.
 */
export function parseTargetRange(text: string): { low: number; high: number } | null {
  const re = /(\d+(?:-\d+\/\d+)?)\s*(?:to|-|–|—)\s*(\d+(?:-\d+\/\d+)?)\s*percent/i;
  const m = re.exec(text);
  if (!m) return null;
  const low = parsePercentToken(m[1]);
  const high = parsePercentToken(m[2]);
  if (low === null || high === null) return null;
  return low <= high ? { low, high } : { low: high, high: low };
}

/**
 * Reads the decision sentence: "decided to raise/lower/maintain the target
 * range ... to 3-3/4 to 4 percent".
 *
 * `lower` and `decrease` are both treated as a cut; `increase` as a hike.
 * Anything else is `unknown`, which scores 0.
 */
export function parseFomcAction(text: string): FomcAction {
  const m = /decided to\s+(raise|lower|decrease|reduce|maintain|increase)\b/i.exec(text);
  if (!m) return 'unknown';
  switch (m[1].toLowerCase()) {
    case 'raise':
    case 'increase':
      return 'raise';
    case 'lower':
    case 'decrease':
    case 'reduce':
      return 'lower';
    default:
      return 'maintain';
  }
}

/**
 * Dissenting voters, when the statement discloses them (§5.2 item 3).
 *
 * The statement reads "Voting against the monetary policy action were Beth M.
 * Hammack and Jeffrey R. Schmidt." The obvious approach of capturing to the
 * next period is wrong: a middle initial is itself a period, so "Beth M." ends
 * the match and truncates the name to "Beth". The text is therefore windowed to
 * a real sentence end — a period NOT preceded by a single capital letter (an
 * initial) and followed by a capitalised word — and the names are pulled out of
 * that window by shape.
 *
 * Returns null when no dissents are disclosed, which is a real observation, and
 * keeps that distinct from "the statement did not say".
 */
export function parseDissents(text: string): string[] | null {
  const anchor = /Voting against[^.]{0,140}?\bwere\b/i.exec(text);
  if (!anchor) return null;
  const start = anchor.index + anchor[0].length;
  const window = text.slice(start, start + 400);
  // A sentence end is a period that is not an initial and is followed by a word.
  const stop = window.search(/(?<![A-Z])\.\s+(?=[A-Z][a-z]{2,})/);
  const scope = stop >= 0 ? window.slice(0, stop) : window;
  // First M. Hammack / Jeffrey R. Schmidt / Janet L. Yellen.
  const names = scope.match(/\b[A-Z][a-z]+(?:\s+[A-Z]\.)*\s+[A-Z][a-z]+\b/g);
  if (!names || names.length === 0) return null;
  return names.map((n) => n.trim());
}

export interface FomcStatement {
  action: FomcAction;
  targetLow: number | null;
  targetHigh: number | null;
  dissents: string[] | null;
  decisionSentence: string | null;
}

/**
 * Parses one statement's HTML into the parts §5.2 asks for.
 *
 * `statementDate` is the ISO date from the release URL (`monetaryYYYYMMDDa.htm`),
 * which is the official release date — more reliable than any date printed in
 * the body, and available without parsing the calendar's layout.
 */
export function parseFomcStatement(html: string, statementDate: string): FomcStatement {
  const text = stripHtml(html);
  const decisionSentence = /decided to[^.]{0,240}\./i.exec(text)?.[0] ?? null;
  const scope = decisionSentence ?? text;
  const range = parseTargetRange(scope);
  return {
    action: parseFomcAction(text),
    targetLow: range?.low ?? null,
    targetHigh: range?.high ?? null,
    dissents: parseDissents(text),
    decisionSentence,
  };
}

/** YYYYMMDD from a statement URL, as an ISO date. */
export function statementDateFromUrl(url: string): string | null {
  const m = /monetary(\d{4})(\d{2})(\d{2})a\.htm/i.exec(url);
  if (!m) return null;
  const iso = `${m[1]}-${m[2]}-${m[3]}`;
  return Number.isNaN(new Date(iso + 'T00:00:00Z').getTime()) ? null : iso;
}

/**
 * The newest statement links on the FOMC calendar page.
 *
 * The calendar exposes every statement as `monetaryYYYYMMDDa.htm`, and the date
 * is in the URL, so "latest" is a max over those dates. The trailing-digit
 * variants (`a1.htm`) are implementation notes and separate dissent statements,
 * not the decision itself, so the match is anchored on `a.htm` exactly.
 *
 * Ordered newest first.
 */
export function latestStatementPaths(html: string, limit: number): { url: string; date: string }[] {
  const out: { url: string; date: string }[] = [];
  const seen = new Set<string>();
  const re = /href="(\/newsevents\/pressreleases\/monetary(\d{8})a)\.htm"/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    if (seen.has(m[1])) continue;
    const date = statementDateFromUrl(`${m[1]}.htm`);
    if (date === null) continue;
    seen.add(m[1]);
    out.push({ url: m[1], date });
  }
  out.sort((a, b) => b.date.localeCompare(a.date));
  return out.slice(0, limit);
}

/**
 * Signed change in the midpoint between two statements, in basis points.
 *
 * Positive means the target range moved UP (more hawkish). Null when either
 * midpoint is unavailable — a change cannot be asserted from a missing level.
 */
export function targetChangeBp(previous: FomcStatement, current: FomcStatement): number | null {
  if (previous.targetLow === null || current.targetLow === null) return null;
  if (previous.targetHigh === null || current.targetHigh === null) return null;
  const prevMid = (previous.targetLow + previous.targetHigh) / 2;
  const currMid = (current.targetLow + current.targetHigh) / 2;
  return Math.round((currMid - prevMid) * 10000) / 100;
}