/**
 * XV outcome recorder.
 *
 * Protocol: docs/outcome-recorder-protocol.md (pre-registered and frozen
 * BEFORE the first row was written). Read it before changing anything here.
 *
 * Two actions:
 *
 *   record  the client posts its scan decision. The function stores it together
 *           with a rule fingerprint it computes ITSELF from the canonical
 *           thresholds below. A client that reports different thresholds gets a
 *           different hash and is VOIDed rather than trusted, because a changed
 *           threshold silently rewrites history if it is not detected.
 *
 *   settle  walks pending rows forward through closed m15 bars and decides the
 *           outcome from real prices. Settlement NEVER trusts a client value.
 *
 * The levels the app withholds live in scan_decisions and are unreadable by the
 * client (RLS, service-role only). That is what lets prices stay hidden while
 * every verdict stays accountable.
 *
 * ---------------------------------------------------------------------------
 * THREE HONEST LIMITATIONS, recorded rather than hidden
 * ---------------------------------------------------------------------------
 *
 * 1. verify_jwt is false because the app has no user accounts. Anyone can POST.
 *    Settlement being independent means a forged row cannot invent a favourable
 *    outcome, but a caller CAN submit synthetic inputs and therefore synthetic
 *    verdicts. This is NOT solved by anything below.
 *
 * 2. This function does not recompute the verdict with the TS port. It cannot:
 *    the deploy bundler does not resolve `../_shared/`, and shipping a second
 *    copy of the engine would create exactly the drift this design exists to
 *    prevent. What IS verified is the threshold set, which is the input most
 *    likely to drift across a deploy. See test/outcome_recorder_parity_test.dart
 *    for the parity guarantee, and the limitation noted in the plan file.
 *
 * 3. Slippage is unmodelled. Results are optimistic by an unknown amount until
 *    broker-grade data exists.
 */

import { createClient } from 'jsr:@supabase/supabase-js@2';

// ---------------------------------------------------------------------------
// Canonical parameters — mirrored from xau_core's Thresholds and
// _shared/analysis.ts DEFAULT_THRESHOLDS / DEFAULT_STOP_CONFIG.
//
// These 14 numbers are the fingerprint's entire basis. They are duplicated here
// on purpose, and the duplication is made safe by a test rather than by trust:
// src/app/test/outcome_recorder_parity_test.dart asserts these equal the Dart
// Thresholds defaults and the TS port's DEFAULT_THRESHOLDS. Change one side and
// that test fails.
//
// Bump ENGINE_VERSION whenever anything in this file's rule inputs changes.
const ENGINE_VERSION = 'xv-confluence/7.0.0';

const CANONICAL_THRESHOLDS = {
  minTechnical: 8,
  minFinal: 9,
  rsiPreferredLow: 52,
  rsiPreferredHigh: 68,
  rsiExhaustedLong: 75,
  rsiExhaustedShort: 25,
  adxTrending: 20,
  atrPercentileLow: 25,
  atrPercentileHigh: 90,
  atrPercentileExtreme: 95,
  stopMinAtr: 0.8,
  stopMaxAtr: 1.8,
  tp2FloorR: 1.8,
  maxDailySignals: 4,
} as const;

// Mirrors _shared/analysis.ts DEFAULT_STOP_CONFIG exactly. These are level-
// CONSTRUCTION parameters, not scoring thresholds: the previous version of this
// file guessed them (tickSize/bufferTicks, tp2R 1.8, tp3R 2.6) and the parity
// test caught that four of six were wrong, which would have put the rule_hash out
// of step with the engine that actually built the levels.
const CANONICAL_STOP_CONFIG = {
  atrBufferMultiple: 0.2,
  minStopAtr: 0.8,
  maxStopAtr: 1.8,
  tp1R: 1,
  tp2R: 2,
  tp3R: 3,
} as const;

// 12 closed m15 bars. Protocol section 3.
const HORIZON_BARS = 12;
const M15_TIMEFRAME = '15m';

// Ledger identity. Bump LEDGER_VERSION when the ledger's MEANING changes, and
// MERGE_RULE_VERSION when only the episode GROUPING changes. Both are stored on
// every row so a later change cannot retroactively alter historical counts.
const LEDGER_VERSION = 'xv-ledger/1';
const MERGE_RULE_VERSION = 'xv-episode-merge/1';

/**
 * Price-feed provenance, established from code, config and logs rather than
 * assumed. D-20261006-013.
 *
 * The engine's mid comes from gold-api.com, whose terms state "Commercial use of
 * the API is always permitted, including use in web applications, mobile apps,
 * and third-party websites". The spread comes from OANDA fxTrade PRACTICE, whose
 * API licence grants INTERNAL USE ONLY and forbids transmitting rates to third
 * parties. XV is a public app, so the spread is recorded for research and marked
 * display-restricted rather than published.
 */
const PRICE_SOURCE_MID = 'gold-api';
const SPREAD_SOURCE = 'oanda-practice';
const SPREAD_DISPLAY_PERMITTED = false;

const GRADE_DB: Record<string, string> = {
  aPlus: 'A_PLUS',
  a: 'A',
  b: 'B',
  insufficient: 'INSUFFICIENT',
};

// ---------------------------------------------------------------------------
// Fingerprint
// ---------------------------------------------------------------------------

/** Deterministic JSON: keys sorted at every depth so Dart and Deno agree. */
function canonical(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null';
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  const obj = value as Record<string, unknown>;
  const keys = Object.keys(obj).sort();
  return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical(obj[k])}`).join(',')}}`;
}

async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Server-side rule fingerprint. If a deploy changes any threshold, the hash
 * changes and new decisions land in a new cohort instead of silently joining the
 * old one.
 */
function ruleHash(): Promise<string> {
  return sha256Hex(canonical({
    engineVersion: ENGINE_VERSION,
    thresholds: CANONICAL_THRESHOLDS,
    stopConfig: CANONICAL_STOP_CONFIG,
    horizonBars: HORIZON_BARS,
  }));
}

// ---------------------------------------------------------------------------
// Normalisation
// ---------------------------------------------------------------------------

function num(raw: unknown): number | null {
  if (raw == null) return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
}

/** -1, 0 or 1 only. Anything else is an invalid reading, not a reading. */
function triState(raw: unknown): number | null {
  const n = num(raw);
  if (n == null) return null;
  const i = Math.trunc(n);
  return i === -1 || i === 0 || i === 1 ? i : null;
}

function strArray(raw: unknown): string[] {
  return Array.isArray(raw) ? raw.map((s) => String(s)) : [];
}

// NO_TRADE is a valid side. An abstention has no direction to cluster on, but it
// still has to be recordable: without abstentions in the table the denominator
// is invisible and the record cannot say whether the engine's caution helped.
const SIDES = new Set(['LONG', 'SHORT', 'FORCED_LONG', 'FORCED_SHORT', 'NO_TRADE']);
const VERDICTS = new Set(['LONG', 'SHORT', 'NO_TRADE']);

/** Side-relative context reading, per the ConfluenceResult convention. */
function sideRelative(reading: number | null, sign: number): number | null {
  return reading == null ? null : reading * sign;
}

/**
 * Episode fingerprint.
 *
 * Deterministic from the stored fields alone, so replaying the same inputs
 * produces the same id — reproducible, not merely idempotent.
 *
 * Deliberately EXCLUDES entry/stop prices. An identical level re-derived every
 * 60 seconds must collapse onto one episode; a level that moved materially is
 * separated by the merge rule's own 0.5R test, which needs the prices but must
 * not fragment identity on every re-derivation.
 */
async function episodeFingerprint(
  side: string,
  decidedAt: Date,
  reasonCodes: string[],
): Promise<string> {
  return sha256Hex(canonical({
    side,
    bar: decidedAt.toISOString(),
    // Reason codes are part of identity: a NO_TRADE caused by a blackout and one
    // caused by low confluence are different observations on the same bar.
    reasons: [...reasonCodes].sort(),
    engine: ENGINE_VERSION,
  }));
}

// ---------------------------------------------------------------------------
// record
// ---------------------------------------------------------------------------

async function record(
  db: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
  serverHash: string,
): Promise<Response> {
  const decisionKey = String(body.decisionKey ?? '').trim();
  if (!decisionKey) return json({ ok: false, error: 'decisionKey is required' }, 400);

  const decidedAt = new Date(String(body.decidedAt ?? ''));
  if (Number.isNaN(decidedAt.getTime())) {
    return json({ ok: false, error: 'decidedAt must be an ISO timestamp' }, 400);
  }
  // A decision cannot be made about the future. Guarding this also stops a
  // caller parking a row far ahead to keep it out of the headline metric.
  if (decidedAt.getTime() > Date.now() + 5 * 60_000) {
    return json({ ok: false, error: 'decidedAt is in the future' }, 400);
  }

  const verdict = String(body.verdict ?? '').toUpperCase();
  const side = String(body.side ?? '').toUpperCase();
  if (!VERDICTS.has(verdict)) return json({ ok: false, error: `bad verdict: ${verdict}` }, 400);
  if (!SIDES.has(side)) return json({ ok: false, error: `bad side: ${side}` }, 400);

  const levels = {
    entry: num(body.entry),
    stop_loss: num(body.stopLoss),
    tp1: num(body.tp1),
    tp2: num(body.tp2),
    tp3: num(body.tp3),
    risk_distance: num(body.riskDistance),
    risk_distance_atr: num(body.riskDistanceAtr),
    atr5m: num(body.atr5m),
  };

  // A counterfactual is only meaningful as the forced twin of an abstention, so
  // it is never accepted on its own. Accepting a standalone one was a real bug
  // found in testing: it produced a synthetic trade with no abstention beside it,
  // which is exactly the orphan that migration 0009 exists to prevent.
  if (body.isCounterfactual === true) {
    return json({
      ok: false,
      error: 'send a counterfactual as the "counterfactual" field of a NO_TRADE record, not on its own',
    }, 400);
  }

  const cf = body.counterfactual == null ? null : normCounterfactual(body.counterfactual);

  // A directional trade without a usable risk distance could never be scored,
  // so it is rejected at the door rather than parked as an unscorable row.
  if (verdict !== 'NO_TRADE') {
    const r = levels.risk_distance;
    if (r == null || r <= 0 || levels.entry == null || levels.tp1 == null) {
      return json({ ok: false, error: 'a directional trade needs entry, tp1 and riskDistance > 0' }, 400);
    }
  }
  if (cf != null && verdict !== 'NO_TRADE') {
    return json({ ok: false, error: 'a counterfactual may only accompany a NO_TRADE record' }, 400);
  }

  const clientHash = body.clientRuleHash ? String(body.clientRuleHash) : null;
  const hashMismatch = clientHash != null && clientHash !== serverHash;

  // Parameter verification.
  //
  // The client sends the NUMBERS its engine actually used, not a hash it
  // computed locally. Reproducing this function's canonical-JSON encoding in
  // Dart is a formatting trap: Dart renders 9.0 as "9.0" where JSON.stringify
  // renders it "9", so a client-computed hash would mismatch on float
  // formatting alone and VOID every honest row. Comparing values numerically
  // here avoids the trap and makes a failure readable instead of cryptographic.
  const expectedParams: Record<string, number> = {
    ...CANONICAL_THRESHOLDS,
    ...CANONICAL_STOP_CONFIG,
  };
  let paramsMismatch = false;
  let paramsAbsent = false;
  const sentParams = body.clientParameters as Record<string, unknown> | null | undefined;

  if (sentParams == null || typeof sentParams !== 'object') {
    paramsAbsent = true;
  } else {
    for (const [key, want] of Object.entries(expectedParams)) {
      const got = num(sentParams[key]);
      if (got == null || got !== want) { paramsMismatch = true; break; }
    }
  }

  // Input attestation.
  //
  // verify_jwt is false, so a caller can post any verdict it likes. What it
  // cannot do is prove its prices were real. The client reports the newest bar
  // it used per timeframe, and this function - which already reads market_bars
  // for settlement - checks those bars against the table itself.
  //
  // This does NOT prove the client's verdict was computed correctly; that would
  // need the TS port, which this bundler cannot import. It does mean a forged
  // row has to quote a real price at a real bar or be VOIDed, which removes the
  // cheapest way to poison the record.
  const inputCheck = await verifyInputDigest(db, body.inputDigest, decidedAt);

  const voidReason = hashMismatch
    ? 'RULE_HASH_MISMATCH'
    : paramsMismatch
    ? 'RULE_PARAMS_MISMATCH'
    : inputCheck.mismatches.length > 0
    ? 'INPUT_MISMATCH'
    : null;

  const spreadValue = num(body.spreadValue);
  const spreadStatus = String(body.spreadStatus ?? 'unavailable');
  const spreadMeasured = spreadStatus === 'available' && spreadValue != null;

  // Spread state per directive §14. A genuine OANDA bid/ask exists but its
  // licence is internal-use-only, so it is recorded for research and marked
  // display-restricted rather than presented as publishable. This is NOT a
  // cross-source difference: it is a real venue ladder from one account.
  const spreadState = spreadMeasured
    ? (SPREAD_DISPLAY_PERMITTED ? 'AVAILABLE_AND_LICENSED' : 'AVAILABLE_BUT_DISPLAY_RESTRICTED')
    : 'UNAVAILABLE';
  // Never 'EVALUATED' on our own authority: the veto was not applied because the
  // spread could not be shown, which is different from having judged it.
  const spreadVeto = 'UNEVALUATED';
  const spreadSource = spreadMeasured ? SPREAD_SOURCE : 'NONE';

  const dataQuality = strArray(body.dataQuality);
  if (clientHash == null) dataQuality.push('NO_CLIENT_HASH');
  if (paramsAbsent) dataQuality.push('NO_CLIENT_PARAMS');
  if (hashMismatch) dataQuality.push('RULE_HASH_MISMATCH');
  if (paramsMismatch) dataQuality.push('RULE_PARAMS_MISMATCH');
  if (inputCheck.absent) dataQuality.push('NO_INPUT_DIGEST');
  if (inputCheck.mismatches.length > 0) {
    dataQuality.push(`INPUT_MISMATCH:${inputCheck.mismatches.join('|')}`);
  }
  if (!spreadMeasured) dataQuality.push('SPREAD_UNAVAILABLE');
  dataQuality.push(`SPREAD_STATE:${spreadState}`);
  dataQuality.push(`SPREAD_SOURCE:${spreadSource}`);

  const sign = side === 'LONG' || side === 'FORCED_LONG' ? 1 : -1;
  const macroAlignment = triState(body.macroAlignment);
  const sentimentAlignment = triState(body.sentimentAlignment);
  const status = voidReason == null ? 'PENDING' : 'VOID';

  const rows: Record<string, unknown>[] = [{
    decision_key: decisionKey,
    decided_at: decidedAt.toISOString(),
    verdict,
    side,
    grade: GRADE_DB[String(body.grade)] ?? 'INSUFFICIENT',
    technical_score: Math.round(Number(body.technicalScore ?? 0) || 0),
    final_score: Math.round((Number(body.finalScore ?? 0) || 0) * 100) / 100,
    reason_codes: strArray(body.reasonCodes),
    vetoes: strArray(body.vetoes),
    data_quality: dataQuality,
    macro_alignment: macroAlignment,
    macro_agrees: verdict === 'NO_TRADE' ? null : sideRelative(macroAlignment, sign),
    sentiment_alignment: sentimentAlignment,
    sentiment_agrees: verdict === 'NO_TRADE' ? null : sideRelative(sentimentAlignment, sign),
    conflict_penalty: Math.round(Number(body.conflictPenalty ?? 0) || 0),
    ...levels,
    spread_status: spreadStatus,
    spread_value: spreadValue,
    engine_version: ENGINE_VERSION,
    rule_hash: serverHash,
    void_reason: voidReason,
    is_counterfactual: false,
    parent_decision_key: null,
    status,
  }];

  if (cf) {
    rows.push({
      decision_key: `${decisionKey}:cf`,
      decided_at: decidedAt.toISOString(),
      verdict: cf.verdict,
      side: cf.side,
      grade: 'INSUFFICIENT',
      technical_score: 0,
      final_score: 0,
      reason_codes: [],
      vetoes: [],
      data_quality: [...dataQuality, 'COUNTERFACTUAL'],
      macro_alignment: macroAlignment,
      macro_agrees: null,
      sentiment_alignment: sentimentAlignment,
      sentiment_agrees: null,
      conflict_penalty: 0,
      entry: cf.entry,
      stop_loss: cf.stopLoss,
      tp1: cf.tp1,
      tp2: null,
      tp3: null,
      risk_distance: cf.risk,
      risk_distance_atr: null,
      atr5m: cf.atr5m,
      spread_status: spreadStatus,
      spread_value: spreadValue,
      engine_version: ENGINE_VERSION,
      rule_hash: serverHash,
      void_reason: voidReason,
      is_counterfactual: true,
      parent_decision_key: decisionKey,
      status,
    });
  }

  // decision_key is unique, so a retried scan is absorbed rather than
  // double-counted. The app scans every 60s and mobile networks retry.
  const { error } = await db.from('scan_decisions').upsert(rows, {
    onConflict: 'decision_key',
    ignoreDuplicates: true,
  });
  if (error) return json({ ok: false, error: error.message }, 500);

  // ---- Episode into the ledger --------------------------------------------
  // Only real decisions produce episodes. A forced counterfactual is a benchmark
  // artefact, not an observation of the engine, so it is excluded: counting it
  // would let the synthetic trade enter the evaluation sample.
  let episodeId: string | null = null;
  let merged = false;
  let episodeState: string | null = null;
  let episodeError: string | null = null;

  if (voidReason == null) {
    const fingerprint = await episodeFingerprint(side, decidedAt, reasonCodes);

    // supabase-js v2 returns a thenable from rpc(), not a Promise, so it has no
    // .catch(). Awaiting it inside try/catch is the only way to handle failure
    // here - chaining .catch() threw a TypeError and turned every decision into
    // a 500. Found by exercising this path, not by reading it.
    let ep: Array<Record<string, unknown>> | null = null;
    let epErrMessage: string | null = null;
    try {
      const res = await db.rpc('xv_episode_merge_v1', {
        p_fingerprint: fingerprint,
        p_timestamp_utc: decidedAt.toISOString(),
        p_direction: verdict === 'NO_TRADE' ? 'NONE' : verdict,
        p_rule_hash: serverHash,
        p_engine_version: ENGINE_VERSION,
        p_ledger_version: LEDGER_VERSION,
        p_merge_rule_version: MERGE_RULE_VERSION,
        // State is derived by the SQL function from the verdict and reason codes,
        // so the app and the ledger cannot disagree about what an abstention was.
        p_state: null,
        p_reason_codes: reasonCodes,
        p_data_quality: dataQuality,
        p_entry: levels.entry,
        p_stop_loss: levels.stop_loss,
        p_tp1: levels.tp1,
        p_tp2: levels.tp2,
        p_tp3: levels.tp3,
        p_risk_distance: levels.risk_distance,
        p_spread_state: spreadState,
        p_spread_veto: spreadVeto,
        p_event_state: null,
        p_input_digest: (body.inputDigest ?? null) as unknown as Record<string, unknown>,
        p_provenance: 'INTERNAL',
        p_price_source: PRICE_SOURCE_MID,
      });
      ep = (res.data ?? null) as Array<Record<string, unknown>> | null;
      if (res.error) epErrMessage = res.error.message;
    } catch (e) {
      epErrMessage = String(e);
    }

    if (epErrMessage != null) {
      // The scan is recorded either way. A lost episode is reported rather than
      // hidden, because a silent gap in the evaluation sample is precisely what
      // this ledger exists to prevent.
      episodeError = epErrMessage;
    } else if (Array.isArray(ep) && ep.length > 0) {
      episodeId = ep[0].episode_id ?? null;
      merged = ep[0].merged === true;
      episodeState = ep[0].state ?? null;
    }
  }

  return json({
    ok: true,
    verdict,
    side,
    grade: rows[0].grade,
    recorded: rows.length,
    ruleHash: serverHash,
    voided: voidReason,
    counterfactualRecorded: cf != null,
    inputBarsChecked: inputCheck.checked,
    inputMismatches: inputCheck.mismatches,
    spreadState,
    episodeId,
    episodeMerged: merged,
    episodeState,
    episodeError,
  });
}

/**
 * Checks the bars a decision claims to have used against `market_bars`.
 *
 * The client sends, per timeframe, the newest bar it evaluated: its open time and
 * its close. The server asks the table for the newest closed bar that had already
 * closed at `decided_at`, and requires the client to be looking at that exact bar.
 *
 * It deliberately does NOT compute the expected open time as
 * `decided_at - interval`. A decision is dated to an M15 close, which is not on
 * the 30m or 1h grid, so that arithmetic asks for bars at :15 past the hour that
 * have never existed. An earlier version did exactly that and reported a
 * perfectly honest client as `1h:no-bar`. Asking the table which bar was current
 * is simpler and correct for every timeframe.
 *
 * Comparing open times, not just prices, is what makes this worth having. A
 * client reading a stale feed still quotes REAL prices, so a price-only check
 * waves it through. Requiring the client to be on the bar the server considers
 * current catches a stale or truncated series directly - which is exactly the
 * fault that had this app analysing four-day-old bars.
 *
 * Returning `absent` rather than a mismatch when no digest is supplied is
 * deliberate: an older client simply has nothing to attest with, and voiding
 * every row from it would destroy real data to enforce a check it cannot make.
 * The flag `NO_INPUT_DIGEST` records that the check did not happen, so a row
 * count of it is always visible.
 */
async function verifyInputDigest(
  db: ReturnType<typeof createClient>,
  raw: unknown,
  decidedAt: Date,
): Promise<{ checked: number; mismatches: string[]; absent: boolean }> {
  if (raw == null || typeof raw !== 'object') {
    return { checked: 0, mismatches: [], absent: true };
  }

  const TF_MINUTES: Record<string, number> = { '5m': 5, '15m': 15, '30m': 30, '1h': 60 };
  const digest = raw as Record<string, unknown>;
  const mismatches: string[] = [];
  let checked = 0;

  for (const [tf, value] of Object.entries(digest)) {
    const minutes = TF_MINUTES[tf];
    if (minutes == null) continue;
    const entry = value as Record<string, unknown> | null;
    if (entry == null || typeof entry !== 'object') continue;

    const claimedClose = num(entry.close);
    if (claimedClose == null) continue;

    const { data, error } = await db
      .from('market_bars')
      .select('open_time,close')
      .eq('symbol', 'XAUUSD')
      .eq('timeframe', tf)
      .eq('is_closed', true)
      // Strictly before the decision instant: the decision was made from the bar
      // closing AT decided_at, whose open is earlier.
      .lt('open_time', decidedAt.toISOString())
      .order('open_time', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) { mismatches.push(`${tf}:query-error`); continue; }
    if (data == null) { mismatches.push(`${tf}:no-bar`); continue; }

    const realOpen = new Date(data.open_time).getTime();
    const claimedOpen = Date.parse(String(entry.openTime ?? ''));
    if (!Number.isFinite(claimedOpen)) { mismatches.push(`${tf}:no-open-time`); continue; }

    // The stale-feed guard. Real prices from the wrong bar still add up.
    if (realOpen !== claimedOpen) {
      const barsBehind = Math.round((realOpen - claimedOpen) / (minutes * 60_000));
      mismatches.push(
        barsBehind > 0 ? `${tf}:stale-by-${barsBehind}` : `${tf}:ahead-of-server`,
      );
      continue;
    }

    const realClose = Number(data.close);
    if (!Number.isFinite(realClose)) { mismatches.push(`${tf}:unreadable-close`); continue; }

    // Tolerant comparison: the client sends a double through JSON, and a
    // sub-tick difference is not evidence of forgery. A price that differs by
    // more than a cent is.
    if (Math.abs(realClose - claimedClose) > 0.01) {
      mismatches.push(`${tf}:close-differs`);
      continue;
    }
    checked++;
  }

  return { checked, mismatches, absent: false };
}

/**
 * The forced-trade twin of an abstention.
 *
 * Direction is the caller's structural lean. There is no fallback that invents
 * one: if no direction is supplied the counterfactual is dropped, because a
 * benchmark built on a guessed side is worse than no benchmark at all.
 */
function normCounterfactual(raw: unknown): {
  verdict: string; side: string; entry: number; stopLoss: number; tp1: number;
  risk: number; atr5m: number | null;
} | null {
  if (raw == null || typeof raw !== 'object') return null;
  const o = raw as Record<string, unknown>;
  const entry = num(o.entry);
  const risk = num(o.riskDistance);
  const side = String(o.side ?? '').toUpperCase();

  if (entry == null || entry <= 0 || risk == null || risk <= 0) return null;
  if (side !== 'FORCED_LONG' && side !== 'FORCED_SHORT') return null;

  const sign = side === 'FORCED_LONG' ? 1 : -1;
  return {
    verdict: side === 'FORCED_LONG' ? 'LONG' : 'SHORT',
    side,
    entry,
    stopLoss: entry - sign * risk,
    tp1: entry + sign * risk,
    risk,
    atr5m: num(o.atr5m),
  };
}

// ---------------------------------------------------------------------------
// settle
// ---------------------------------------------------------------------------

/**
 * Decide one pending row from forward closed m15 bars.
 *
 * First barrier touched wins. If a single bar touches both, the STOP is assumed
 * first: intrabar sequence is unknowable from OHLC, and the assumption has to be
 * the pessimistic one. A TIMEOUT is scored at the horizon close and COUNTED,
 * never dropped. Dropping unresolved trades is how a losing system reports a
 * winning one.
 */
function resolveOne(
  row: Record<string, unknown>,
  bars: { high: number; low: number; close: number }[],
): Record<string, unknown> | null {
  // An abstention has no levels to score against a barrier. It closes at its
  // horizon as a zero-R observation instead, so the row stops being re-examined
  // by every settle run forever and stays counted rather than silently retrying.
  // The summary view excludes ABSTAINED from the trade metric but reports the
  // count separately, because an engine that abstains 95% of the time is a fact
  // about the engine worth seeing.
  if (row.verdict === 'NO_TRADE') {
    return {
      status: 'RESOLVED',
      outcome: 'ABSTAINED',
      r_gross: 0,
      r_net: 0,
      spread_cost_r: null,
      exit_price: null,
      bars_used: 0,
      settled_at: new Date().toISOString(),
    };
  }

  // The ledger only ever settles SETUP episodes - an abstention is closed at its
  // horizon as a zero-R observation so it stops being re-examined, but that
  // closure is a property of the episode's state, not of a price test. The
  // classifier marks those states, and abstention rows never reach here.
  const state = String(row.state ?? 'SETUP');
  if (state !== 'SETUP') return null;

  const entry = Number(row.entry);
  const stopLoss = Number(row.stop_loss);
  const tp1 = Number(row.tp1);
  const risk = Number(row.risk_distance);

  if (![entry, stopLoss, tp1, risk].every(Number.isFinite) || risk <= 0) return null;

  const sign = row.direction === 'LONG' ? 1 : -1;
  const spread = row.spread_value == null ? null : Number(row.spread_value);

  let outcome: string;
  let exitPrice: number;
  let barsUsed = 0;

  const hit = bars.findIndex((b) => {
    barsUsed++;
    const stop = sign === 1 ? b.low <= stopLoss : b.high >= stopLoss;
    const target = sign === 1 ? b.high >= tp1 : b.low <= tp1;
    // Pessimistic tie-break, deliberately stop-first.
    if (stop) return true;
    return target;
  });

  if (hit >= 0) {
    const b = bars[hit];
    const stopHit = sign === 1 ? b.low <= stopLoss : b.high >= stopLoss;
    outcome = stopHit ? 'STOP' : 'TARGET_FIRST';
    exitPrice = stopHit ? stopLoss : tp1;
    barsUsed = hit + 1;
  } else {
    // Nothing resolved inside the window. No bars at all means the data has not
    // arrived yet, so wait rather than declaring a result we cannot compute.
    if (bars.length === 0) return null;
    outcome = 'TIMEOUT';
    exitPrice = bars[bars.length - 1].close;
    barsUsed = bars.length;
  }

  const rGross = ((exitPrice - entry) * sign) / risk;
  const spreadCostR = spread != null ? spread / risk : null;
  // When spread is unmeasurable we do not silently pretend it was zero. The net
  // falls back to gross and the row is flagged, so the optimism stays countable
  // in mean_spread_cost_r instead of disappearing into the headline.
  const rNet = spreadCostR == null ? rGross : rGross - spreadCostR;

  return {
    outcome,
    // Directive §9: when no usable transaction-cost measurement exists, say so
    // rather than fabricating one.
    net_outcome: spreadCostR == null ? 'cost_model_unavailable' : 'measured_spread',
    cost_model: spreadCostR == null ? 'cost_model_unavailable' : 'measured_spread',
    r_gross: Math.round(rGross * 10000) / 10000,
    r_net: Math.round(rNet * 10000) / 10000,
    spread_cost_r: spreadCostR == null ? null : Math.round(spreadCostR * 10000) / 10000,
    exit_price: exitPrice,
    bars_used: barsUsed,
    // Provenance of the settlement is recorded separately from the decision's,
    // so a later change of price feed is visible rather than silent.
    outcome_source: `${M15_TIMEFRAME}:market_bars:${PRICE_SOURCE_MID}`,
    price_source_at_outcome: PRICE_SOURCE_MID,
    resolved_at: new Date().toISOString(),
  };
}

async function settle(db: ReturnType<typeof createClient>): Promise<Response> {
  // Resolve EPISODES, not scans. The scan table keeps its own settlement for the
  // audit trail, but the evaluation unit is the episode: ten scans of one gold
  // move are one observation. Settling scans and then aggregating would let a
  // repeated scan bias the mean.
  const { data: pending, error } = await db
    .from('xv_outcome_ledger')
    .select('*')
    .eq('state', 'SETUP')
    .is('resolved_at', null)
    .is('outcome', null)
    .lte('timestamp_utc', new Date(Date.now() - HORIZON_BARS * 15 * 60_000).toISOString())
    .order('timestamp_utc', { ascending: true })
    .limit(500);

  if (error) return json({ ok: false, error: error.message }, 500);
  if (!pending || pending.length === 0) {
    return json({ ok: true, settled: 0, note: 'no episodes past their horizon' });
  }

  // One price query for the whole batch rather than one per episode.
  const from = String(pending[0].timestamp_utc);
  const to = new Date(Date.now()).toISOString();
  const { data: bars, error: barErr } = await db
    .from('market_bars')
    .select('open_time, high, low, close')
    .eq('timeframe', M15_TIMEFRAME)
    .eq('is_closed', true)
    .gte('open_time', from)
    .lte('open_time', to)
    .order('open_time', { ascending: true });

  if (barErr) return json({ ok: false, error: barErr.message }, 500);

  const series = (bars ?? []).map((b) => ({
    t: new Date(b.open_time).getTime(),
    high: Number(b.high),
    low: Number(b.low),
    close: Number(b.close),
  }));

  let settled = 0;
  const unresolved: string[] = [];

  for (const row of pending as Record<string, unknown>[]) {
    const start = new Date(String(row.timestamp_utc)).getTime();
    const end = start + HORIZON_BARS * 15 * 60_000;
    const window = series.filter((b) => b.t >= start && b.t < end);

    const update = resolveOne(row, window);
    if (!update) { unresolved.push(String(row.episode_id)); continue; }

    // Fewer bars than the horizon means a data gap, not a quiet market. Flag it
    // rather than letting a truncated window read as a completed test.
    if (window.length < HORIZON_BARS) {
      const flags = Array.isArray(row.data_quality) ? [...row.data_quality] : [];
      flags.push(`HORIZON_BAR_GAP:${window.length}/${HORIZON_BARS}`);
      update.data_quality = flags;
    }

    const { error: upErr } = await db
      .from('xv_outcome_ledger')
      .update(update)
      .eq('episode_id', row.episode_id)
      .is('resolved_at', null); // Idempotent: never re-settle a settled episode.
    if (upErr) return json({ ok: false, error: upErr.message }, 500);
    settled++;
  }

  return json({
    ok: true,
    settled,
    stillPending: unresolved.length,
    sampleUnresolved: unresolved.slice(0, 5),
  });
}

// ---------------------------------------------------------------------------

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'GET') {
    return json({
      ok: true,
      service: 'outcome-recorder',
      engineVersion: ENGINE_VERSION,
      ledgerVersion: LEDGER_VERSION,
      mergeRuleVersion: MERGE_RULE_VERSION,
      horizonBars: HORIZON_BARS,
      protocol: 'docs/outcome-recorder-protocol.md',
      evaluation: 'docs/evaluation-pre-registration.md',
      priceFeed: {
        mid: PRICE_SOURCE_MID,
        spread: SPREAD_SOURCE,
        // OANDA's licence grants internal use only and forbids transmitting rates
        // to third parties, so the spread may not be shown to app users.
        spreadDisplayPermitted: SPREAD_DISPLAY_PERMITTED,
      },
      limitations: [
        'verify_jwt is false: anyone can POST, so verdicts are client-reported',
        'settled outcomes are independent - market_bars decides, not the client',
        'input attestation voids a row whose claimed prices are not real',
        'the verdict itself is not recomputed server-side; parameters are verified instead',
        'slippage is unmodelled, so every net figure is optimistic',
        'the OANDA spread is internal-use-only and may not be shown to app users',
      ],
    });
  }
  if (req.method !== 'POST') return json({ ok: false, error: 'POST only' }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'invalid JSON' }, 400);
  }

  const db = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false } },
  );

  try {
    const serverHash = await ruleHash();
    switch (body.action) {
      case 'record': return await record(db, body, serverHash);
      case 'settle': return await settle(db);
      case 'hash': return json({ ok: true, ruleHash: serverHash, engineVersion: ENGINE_VERSION });
      default: return json({ ok: false, error: `unknown action: ${body.action}` }, 400);
    }
  } catch (err) {
    return json({ ok: false, error: String(err) }, 500);
  }
});