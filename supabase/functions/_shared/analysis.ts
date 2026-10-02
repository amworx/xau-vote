/**
 * Analysis engine port: indicators, confluence, stop planning and the
 * multi-timeframe scanner (methodology §2, §4, §8, §11, §12, §21).
 *
 * SOURCE OF TRUTH: the Dart implementation in src/xau_core.
 * Supabase Edge Functions run Deno, not Dart, so this mirrors the Dart modules
 * analysis/{indicators,confluence,calendar_lock,stop_plan,scanner}.ts.
 * Any behaviour change must land in Dart FIRST, be mirrored here, then be
 * re-validated against golden vectors.
 *
 * Two invariants carried over verbatim from Dart, because breaking either would
 * produce confidently wrong output rather than an obvious failure:
 *
 *  1. Insufficient data yields null/undefined, never a default. A 200-period
 *     EMA fed 30 bars must not report 0, which would read as "flat".
 *  2. Spread is only ever a genuine venue Ask - Bid. There is no code path
 *     that derives a spread from two price sources (ratified option (a)).
 */

export type Tf = '5m' | '15m' | '30m' | '1h';
export type Side = 'long' | 'short';
export type Grade = 'aPlus' | 'a' | 'b' | 'insufficient';
export type Verdict = 'long' | 'short' | 'noTrade';
export type SpreadStatus = 'available' | 'unavailable';

export interface Bar {
  t: number;
  o: number;
  h: number;
  l: number;
  c: number;
  v?: number | null;
  closed: boolean;
  degraded: boolean;
}

export interface IndicatorSeries { [i: number]: number | null; }

// ---------------------------------------------------------------- indicators

/** Exponential MA seeded with the SMA of the first `period` values. */
export function ema(values: number[], period: number): IndicatorSeries {
  const out: IndicatorSeries = {};
  if (period <= 0 || values.length < period) return out;
  let sum = 0;
  for (let i = 0; i < period; i++) sum += values[i];
  let prev = sum / period;
  out[period - 1] = prev;
  const k = 2 / (period + 1);
  for (let i = period; i < values.length; i++) {
    prev = (values[i] - prev) * k + prev;
    out[i] = prev;
  }
  return out;
}

function rsiValue(gain: number, loss: number): number {
  if (loss === 0) return gain === 0 ? 50 : 100;
  return 100 - 100 / (1 + gain / loss);
}

/** Wilder's RSI. */
export function rsi(values: number[], period = 14): IndicatorSeries {
  const out: IndicatorSeries = {};
  if (period <= 0 || values.length <= period) return out;
  let gainSum = 0;
  let lossSum = 0;
  for (let i = 1; i <= period; i++) {
    const d = values[i] - values[i - 1];
    if (d >= 0) gainSum += d;
    else lossSum -= d;
  }
  let gain = gainSum / period;
  let loss = lossSum / period;
  out[period] = rsiValue(gain, loss);
  for (let i = period + 1; i < values.length; i++) {
    const d = values[i] - values[i - 1];
    gain = (gain * (period - 1) + (d > 0 ? d : 0)) / period;
    loss = (loss * (period - 1) + (d < 0 ? -d : 0)) / period;
    out[i] = rsiValue(gain, loss);
  }
  return out;
}

export interface MacdResult { macd: IndicatorSeries; signal: IndicatorSeries; histogram: IndicatorSeries }

export function macd(values: number[], fast = 12, slow = 26, signalPeriod = 9): MacdResult {
  const ef = ema(values, fast);
  const es = ema(values, slow);
  const line: IndicatorSeries = {};
  for (const key of Object.keys(ef)) {
    const i = Number(key);
    const f = ef[i];
    const s = es[i];
    if (f != null && s != null) line[i] = f - s;
  }
  // The signal EMA must run over defined MACD values only; feeding it a
  // null-padded series would shift it by the fast-EMA warm-up offset.
  const defined: { i: number; v: number }[] = [];
  for (const key of Object.keys(line)) {
    const i = Number(key);
    const v = line[i];
    if (v != null) defined.push({ i, v });
  }
  const sig: IndicatorSeries = {};
  const hist: IndicatorSeries = {};
  if (defined.length >= signalPeriod) {
    const sigSeries = ema(defined.map((d) => d.v), signalPeriod);
    for (const key of Object.keys(sigSeries)) {
      const j = Number(key);
      const v = sigSeries[j];
      if (v != null) {
        sig[defined[j].i] = v;
        hist[defined[j].i] = defined[j].v - v;
      }
    }
  }
  return { macd: line, signal: sig, histogram: hist };
}

export function trueRange(prev: Bar, cur: Bar): number {
  const hl = cur.h - cur.l;
  const hc = Math.abs(cur.h - prev.c);
  const lc = Math.abs(cur.l - prev.c);
  return Math.max(hl, hc, lc);
}

/** Wilder-smoothed ATR. */
export function atr(bars: Bar[], period = 14): IndicatorSeries {
  const out: IndicatorSeries = {};
  if (bars.length < period + 1) return out;
  const trs: number[] = [];
  for (let i = 1; i < bars.length; i++) trs.push(trueRange(bars[i - 1], bars[i]));
  if (trs.length < period) return out;
  let prev = 0;
  for (let i = 0; i < period; i++) prev += trs[i];
  prev /= period;
  out[period] = prev;
  for (let i = period; i < trs.length; i++) {
    prev = (prev * (period - 1) + trs[i]) / period;
    out[i + 1] = prev;
  }
  return out;
}

export interface AdxResult { adx: IndicatorSeries; plusDi: IndicatorSeries; minusDi: IndicatorSeries }

export function adx(bars: Bar[], period = 14): AdxResult {
  const n = bars.length;
  const adxOut: IndicatorSeries = {};
  const plusOut: IndicatorSeries = {};
  const minusOut: IndicatorSeries = {};
  if (n < period * 2 + 1) return { adx: adxOut, plusDi: plusOut, minusDi: minusOut };

  const pdm: number[] = [];
  const mdm: number[] = [];
  const trs: number[] = [];
  for (let i = 1; i < n; i++) {
    const up = bars[i].h - bars[i - 1].h;
    const dn = bars[i - 1].l - bars[i].l;
    pdm.push(up > dn && up > 0 ? up : 0);
    mdm.push(dn > up && dn > 0 ? dn : 0);
    trs.push(trueRange(bars[i - 1], bars[i]));
  }

  const di = (d: number, t: number): number => (t === 0 ? 0 : (d / t) * 100);
  const dxOf = (p: number, t: number, m: number): number => {
    if (t === 0) return 0;
    const pp = (p / t) * 100;
    const mm = (m / t) * 100;
    const sum = pp + mm;
    return sum === 0 ? 0 : (Math.abs(pp - mm) / sum) * 100;
  };

  let tr = 0;
  let p = 0;
  let m = 0;
  for (let i = 0; i < period; i++) {
    tr += trs[i];
    p += pdm[i];
    m += mdm[i];
  }
  plusOut[period] = di(p, tr);
  minusOut[period] = di(m, tr);
  const dx: number[] = [dxOf(p, tr, m)];
  const idx: number[] = [period];

  for (let i = period; i < trs.length; i++) {
    tr = tr - tr / period + trs[i];
    p = p - p / period + pdm[i];
    m = m - m / period + mdm[i];
    const j = i + 1;
    plusOut[j] = di(p, tr);
    minusOut[j] = di(m, tr);
    dx.push(dxOf(p, tr, m));
    idx.push(j);
  }

  if (dx.length >= period) {
    let prev = 0;
    for (let i = 0; i < period; i++) prev += dx[i];
    prev /= period;
    adxOut[idx[period - 1]] = prev;
    for (let i = period; i < dx.length; i++) {
      prev = (prev * (period - 1) + dx[i]) / period;
      adxOut[idx[i]] = prev;
    }
  }
  return { adx: adxOut, plusDi: plusOut, minusDi: minusOut };
}

export interface BollingerResult { upper: IndicatorSeries; middle: IndicatorSeries; lower: IndicatorSeries; bandwidth: IndicatorSeries }

export function bollinger(values: number[], period = 20, mult = 2): BollingerResult {
  const mid = ema(values, period);
  const up: IndicatorSeries = {};
  const lo: IndicatorSeries = {};
  const bw: IndicatorSeries = {};
  for (const key of Object.keys(mid)) {
    const i = Number(key);
    const m = mid[i];
    if (m == null || i < period - 1) continue;
    let sumSq = 0;
    for (let j = i - period + 1; j <= i; j++) {
      const d = values[j] - m;
      sumSq += d * d;
    }
    const sd = Math.sqrt(sumSq / period);
    up[i] = m + mult * sd;
    lo[i] = m - mult * sd;
    bw[i] = m === 0 ? null : (mult * 2 * sd) / m;
  }
  return { upper: up, middle: mid, lower: lo, bandwidth: bw };
}

export interface Swing { index: number; price: number; isHigh: boolean }

/** Fractal swing pivots. The trailing `lookback` bars cannot confirm one. */
export function swings(bars: Bar[], lookback = 2): Swing[] {
  if (lookback < 1 || bars.length < lookback * 2 + 1) return [];
  const out: Swing[] = [];
  for (let i = lookback; i < bars.length - lookback; i++) {
    let isHigh = true;
    let isLow = true;
    for (let j = i - lookback; j <= i + lookback; j++) {
      if (j === i) continue;
      if (bars[j].h >= bars[i].h) isHigh = false;
      if (bars[j].l <= bars[i].l) isLow = false;
    }
    if (isHigh) out.push({ index: i, price: bars[i].h, isHigh: true });
    if (isLow) out.push({ index: i, price: bars[i].l, isHigh: false });
  }
  return out;
}

export function lastSwingLow(all: Swing[], upTo: number): Swing | null {
  for (let i = all.length - 1; i >= 0; i--) {
    if (!all[i].isHigh && all[i].index <= upTo) return all[i];
  }
  return null;
}

export function lastSwingHigh(all: Swing[], upTo: number): Swing | null {
  for (let i = all.length - 1; i >= 0; i--) {
    if (all[i].isHigh && all[i].index <= upTo) return all[i];
  }
  return null;
}

/** Percentile rank of the latest ATR in its own recent window. */
export function atrPercentile(history: number[], lookback = 100): number | null {
  const vals = history.filter((v) => Number.isFinite(v) && v > 0);
  if (vals.length < 20) return null;
  const window = vals.length > lookback ? vals.slice(vals.length - lookback) : vals;
  const latest = window[window.length - 1];
  let below = 0;
  for (const v of window) if (v <= latest) below++;
  return (below / window.length) * 100;
}

function lastOf(s: IndicatorSeries): number | null {
  const keys = Object.keys(s);
  for (let i = keys.length - 1; i >= 0; i--) {
    const v = s[Number(keys[i])];
    if (v != null) return v;
  }
  return null;
}

// ---------------------------------------------------------------- confluence

export type ReasonCode =
  | 'h1TrendAligned' | 'h1RsiFavorable' | 'h1MacdAligned' | 'm30StructureAligned'
  | 'm15PullbackToZone' | 'm15CandleConfirmation' | 'm5TriggerPresent'
  | 'adxConfirmsTrend' | 'volatilitySuitable' | 'macroSupports' | 'sentimentSupports'
  | 'v1Blackout' | 'v2SpreadUnevaluated' | 'v3DataStale' | 'v4VolatilityExtreme'
  | 'v5PoorRewardRisk' | 'v6DirectionConflict' | 'v7DailyLimit' | 'v8SessionClosed'
  | 'v9Duplicate' | 'v10ConfirmationLow' | 'v11H1Neutral' | 'v12LowConfluence'
  | 'v13BadStopDistance' | 'v14RsiExhausted' | 'v15ExtendedEntry';

export interface TimeframeState {
  tf: Tf;
  close: number | null;
  ema20: number | null;
  ema50: number | null;
  ema200: number | null;
  rsi14: number | null;
  macdHistogram: number | null;
  adx14: number | null;
  plusDi: number | null;
  minusDi: number | null;
  atr: number | null;
  atrPercentile: number | null;
  swingLow: number | null;
  swingHigh: number | null;
  hasPattern: boolean;
}

export interface Thresholds {
  minTechnical: number;
  minFinal: number;
  rsiPreferredLow: number;
  rsiPreferredHigh: number;
  rsiExhaustedLong: number;
  rsiExhaustedShort: number;
  adxTrending: number;
  atrPercentileLow: number;
  atrPercentileHigh: number;
  atrPercentileExtreme: number;
  stopMinAtr: number;
  stopMaxAtr: number;
  tp2FloorR: number;
  maxDailySignals: number;
}

export const DEFAULT_THRESHOLDS: Thresholds = {
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
};

export interface ConfluenceInput {
  direction: Side;
  h1: TimeframeState;
  m30: TimeframeState;
  m15: TimeframeState;
  m5: TimeframeState;
  atr5m: number | null;
  macroAlignment: number | null;
  sentimentAlignment: number | null;
  spreadStatus: SpreadStatus;
  blackout: boolean;
  dataStale: boolean;
  sessionOpen: boolean;
  signalsEmittedToday: number;
  maxSignalsPerDay: number;
  duplicate: boolean;
  blockedByLevel: boolean;
}

export interface ConfluenceResult {
  verdict: Verdict;
  grade: Grade;
  reasonCodes: ReasonCode[];
  vetoed: ReasonCode[];
  technicalScore: number;
  finalScore: number;
  conflictPenalty: number;
}

const EMPTY_TF = (tf: Tf): TimeframeState => ({
  tf, close: null, ema20: null, ema50: null, ema200: null, rsi14: null,
  macdHistogram: null, adx14: null, plusDi: null, minusDi: null, atr: null,
  atrPercentile: null, swingLow: null, swingHigh: null, hasPattern: false,
});

const CONFIRMATIONS: ReasonCode[] = [
  'h1TrendAligned', 'h1RsiFavorable', 'h1MacdAligned', 'm30StructureAligned',
  'm15PullbackToZone', 'm15CandleConfirmation', 'm5TriggerPresent', 'adxConfirmsTrend',
];

function emaScore(s: TimeframeState, bull: boolean): number {
  const { close: c, ema20: e20, ema50: e50, ema200: e200 } = s;
  if (c == null || e20 == null || e50 == null || e200 == null) return 0;
  const clean = bull ? c > e20 && e20 > e50 && e50 > e200 : c < e20 && e20 < e50 && e50 < e200;
  if (clean) return 2;
  const sideOf200 = bull ? c > e200 : c < e200;
  return sideOf200 ? 1 : 0;
}

function structureScore(s: TimeframeState, bull: boolean): number {
  const { close: c, swingHigh: hi, swingLow: lo } = s;
  if (c == null || hi == null || lo == null) return 0;
  if (bull) {
    if (c > hi) return 2;
    if (c > lo) return 1;
    return 0;
  }
  if (c < lo) return 2;
  if (c < hi) return 1;
  return 0;
}

function pullbackToZone(s: TimeframeState): boolean {
  const { close: c, ema20: e20, ema50: e50 } = s;
  if (c == null || e20 == null || e50 == null) return false;
  const hiZone = Math.max(e20, e50);
  const loZone = Math.min(e20, e50);
  return c >= loZone && c <= hiZone;
}

function extendedEntry(s: TimeframeState, bull: boolean): boolean {
  const { close: c, ema20: e20, atr: a } = s;
  if (c == null || e20 == null) return false;
  const ref = a != null && a > 0 ? a : c * 0.02;
  if (Math.abs(c - e20) <= ref) return false;
  return bull ? c > e20 : c < e20;
}

export function evaluateConfluence(
  input: ConfluenceInput,
  t: Thresholds = DEFAULT_THRESHOLDS,
): ConfluenceResult {
  const reasons: ReasonCode[] = [];
  const vetoes: ReasonCode[] = [];
  const bull = input.direction === 'long';
  const credit = (c: ReasonCode) => reasons.push(c);
  const veto = (c: ReasonCode) => vetoes.push(c);

  if (input.dataStale || !input.h1.ema200) veto('v3DataStale');
  if (input.blackout) veto('v1Blackout');
  // UNEVALUATED is a data-quality note, never a veto and never a pass.
  if (input.spreadStatus === 'unavailable') credit('v2SpreadUnevaluated');
  if (!input.sessionOpen) veto('v8SessionClosed');
  const dailyCap = input.maxSignalsPerDay === 0 ? t.maxDailySignals : input.maxSignalsPerDay;
  if (input.signalsEmittedToday >= dailyCap) veto('v7DailyLimit');
  if (input.duplicate) veto('v9Duplicate');

  const atrPct = input.m5.atrPercentile;
  if (atrPct != null && atrPct >= t.atrPercentileExtreme) veto('v4VolatilityExtreme');

  let technical = 0;

  if (emaScore(input.h1, bull) === 2) credit('h1TrendAligned');
  technical += emaScore(input.h1, bull);

  const h1Rsi = input.h1.rsi14;
  if (h1Rsi != null) {
    if (bull && h1Rsi >= t.rsiExhaustedLong) veto('v14RsiExhausted');
    else if (!bull && h1Rsi <= t.rsiExhaustedShort) veto('v14RsiExhausted');
    else {
      // Side-aware preferred zone: 52-68 long, mirrored 32-48 short.
      const lo = bull ? t.rsiPreferredLow : 100 - t.rsiPreferredHigh;
      const hi = bull ? t.rsiPreferredHigh : 100 - t.rsiPreferredLow;
      if (h1Rsi >= lo && h1Rsi <= hi) {
        technical += 1;
        credit('h1RsiFavorable');
      }
    }
  }

  const hist = input.h1.macdHistogram;
  if (hist != null && (bull ? hist > 0 : hist < 0)) {
    technical += 1;
    credit('h1MacdAligned');
  }

  const structure = structureScore(input.m30, bull);
  if (structure > 0) credit('m30StructureAligned');
  technical += structure;

  if (pullbackToZone(input.m15)) {
    credit('m15PullbackToZone');
    technical += 1;
    if (input.m15.hasPattern) {
      technical += 1;
      credit('m15CandleConfirmation');
    }
  }

  if (input.m5.hasPattern) {
    credit('m5TriggerPresent');
    technical += 2;
  }

  const adxVal = input.m30.adx14 ?? input.m15.adx14;
  const diFav = bull
    ? (input.m30.plusDi ?? 0) > (input.m30.minusDi ?? 0)
    : (input.m30.minusDi ?? 0) > (input.m30.plusDi ?? 0);
  if (adxVal != null && adxVal >= t.adxTrending && diFav) {
    technical += 1;
    credit('adxConfirmsTrend');
  }

  if (atrPct != null && atrPct >= t.atrPercentileLow && atrPct < t.atrPercentileHigh) {
    technical += 1;
    credit('volatilitySuitable');
  }

  if (extendedEntry(input.m15, bull)) veto('v15ExtendedEntry');

  const confirmations = reasons.filter((r) => CONFIRMATIONS.includes(r)).length;
  if (technical > 0 && confirmations < 2) veto('v10ConfirmationLow');

  if (input.blockedByLevel) veto('v5PoorRewardRisk');

  let conflictPenalty = 0;
  const macro = input.macroAlignment;
  if (macro != null) {
    if (macro > 0) credit('macroSupports');
    if (macro < 0) {
      conflictPenalty += 1;
      veto('v6DirectionConflict');
    }
  }
  // Slow sentiment penalises confidence but never reverses a trade.
  if (input.sentimentAlignment != null && input.sentimentAlignment > 0) credit('sentimentSupports');
  if (input.sentimentAlignment != null && input.sentimentAlignment < 0) conflictPenalty += 1;

  const finalScore = technical + 2 * (macro ?? 0) + (input.sentimentAlignment ?? 0) - conflictPenalty;

  if (technical < t.minTechnical) veto('v12LowConfluence');
  if (finalScore < t.minFinal) veto('v12LowConfluence');

  const noTrade = vetoes.length > 0;
  let grade: Grade;
  if (noTrade) {
    grade = 'insufficient';
  } else if (technical >= 11 && finalScore >= 11 && macro !== -1) {
    grade = 'aPlus';
  } else if (technical >= 10 && finalScore >= 10) {
    grade = 'a';
  } else {
    grade = 'b';
  }

  return {
    verdict: noTrade ? 'noTrade' : bull ? 'long' : 'short',
    grade,
    reasonCodes: [...reasons, ...vetoes],
    vetoed: vetoes,
    technicalScore: technical,
    finalScore,
    conflictPenalty,
  };
}

// ---------------------------------------------------------------- stop plan

export interface StopPlan {
  valid: boolean;
  entry: number;
  stopLoss: number | null;
  tp1: number | null;
  tp2: number | null;
  tp3: number | null;
  riskDistance: number | null;
  riskDistanceAtr: number | null;
  spreadStatus: SpreadStatus;
  bufferSource: string;
  rejectionReason: string | null;
  tp2R: number | null;
}

export interface StopConfig {
  atrBufferMultiple: number;
  minStopAtr: number;
  maxStopAtr: number;
  tp1R: number;
  tp2R: number;
  tp3R: number;
}

export const DEFAULT_STOP_CONFIG: StopConfig = {
  atrBufferMultiple: 0.2,
  minStopAtr: 0.8,
  maxStopAtr: 1.8,
  tp1R: 1,
  tp2R: 2,
  tp3R: 3,
};

function reject(reason: string, spreadStatus: SpreadStatus, bufferSource: string): StopPlan {
  return {
    valid: false, entry: 0, stopLoss: null, tp1: null, tp2: null, tp3: null,
    riskDistance: null, riskDistanceAtr: null, spreadStatus, bufferSource,
    rejectionReason: reason, tp2R: null,
  };
}

export function buildStopPlan(args: {
  direction: Side;
  entry: number;
  atr5m: number;
  swingLow?: number | null;
  swingHigh?: number | null;
  spreadStatus: SpreadStatus;
  /** Only a genuine venue spread may be passed here. */
  genuineSpread?: number | null;
  config?: StopConfig;
}): StopPlan {
  const cfg = args.config ?? DEFAULT_STOP_CONFIG;
  const bull = args.direction === 'long';
  const spreadStatus = args.spreadStatus;

  if (!Number.isFinite(args.atr5m) || args.atr5m <= 0) {
    return reject('ATR_UNAVAILABLE', spreadStatus, 'none');
  }
  if (!Number.isFinite(args.entry) || args.entry <= 0) {
    return reject('ENTRY_UNAVAILABLE', spreadStatus, 'none');
  }

  const hasGenuine =
    spreadStatus === 'available' &&
    args.genuineSpread != null &&
    Number.isFinite(args.genuineSpread) &&
    args.genuineSpread > 0;
  const atrBuffer = cfg.atrBufferMultiple * args.atr5m;
  const buffer = hasGenuine ? Math.max(atrBuffer, args.genuineSpread! * 2) : atrBuffer;
  const bufferSource = hasGenuine ? 'max(0.20*ATR, spread*2)' : '0.20*ATR';

  let anchor: number;
  if (bull) {
    const lo = args.swingLow;
    // Without a confirmed swing there is no structural stop; refuse rather
    // than substituting the ATR midpoint.
    if (lo == null || !Number.isFinite(lo)) return reject('NO_CONFIRMED_SWING_LOW', spreadStatus, 'none');
    if (lo >= args.entry) return reject('SWING_LOW_ABOVE_ENTRY', spreadStatus, 'none');
    anchor = lo;
  } else {
    const hi = args.swingHigh;
    if (hi == null || !Number.isFinite(hi)) return reject('NO_CONFIRMED_SWING_HIGH', spreadStatus, 'none');
    if (hi <= args.entry) return reject('SWING_HIGH_BELOW_ENTRY', spreadStatus, 'none');
    anchor = hi;
  }

  const stopRaw = bull ? anchor - buffer : anchor + buffer;
  const distance = Math.abs(args.entry - stopRaw);
  const distanceAtr = distance / args.atr5m;

  // A structural stop wider than the envelope is rejected, never widened.
  if (distanceAtr > cfg.maxStopAtr) return reject('STRUCTURAL_STOP_TOO_WIDE', spreadStatus, bufferSource);

  let stop = stopRaw;
  let source = bufferSource;
  if (distanceAtr < cfg.minStopAtr) {
    stop = bull ? args.entry - cfg.minStopAtr * args.atr5m : args.entry + cfg.minStopAtr * args.atr5m;
    source = `${bufferSource} widened to ${cfg.minStopAtr}xATR floor`;
  }

  const risk = Math.abs(args.entry - stop);
  if (!(risk > 0)) return reject('NON_POSITIVE_RISK', spreadStatus, source);

  const at = (r: number): number => (bull ? args.entry + risk * r : args.entry - risk * r);
  const tp1 = at(cfg.tp1R);
  const tp2 = at(cfg.tp2R);
  const tp3 = at(cfg.tp3R);

  return {
    valid: true,
    entry: args.entry,
    stopLoss: stop,
    tp1,
    tp2,
    tp3,
    riskDistance: risk,
    riskDistanceAtr: risk / args.atr5m,
    spreadStatus,
    bufferSource: source,
    rejectionReason: null,
    tp2R: Math.abs(tp2 - args.entry) / risk,
  };
}

// ------------------------------------------------------------------- scanner

export interface VenueSpread {
  status: SpreadStatus;
  bid: number | null;
  ask: number | null;
  source: string;
  value: number | null;
}

export function genuineSpread(bid: number, ask: number, source: string): VenueSpread {
  const ok = Number.isFinite(bid) && Number.isFinite(ask) && ask >= bid;
  return {
    status: ok ? 'available' : 'unavailable',
    bid: Number.isFinite(bid) ? bid : null,
    ask: Number.isFinite(ask) ? ask : null,
    source: ok ? source : 'NONE',
    value: ok ? Math.round((ask - bid) * 1000) / 1000 : null,
  };
}

export function unavailableSpread(): VenueSpread {
  return { status: 'unavailable', bid: null, ask: null, source: 'NONE', value: null };
}

export interface ScanInput {
  direction: Side | null;
  m5: Bar[];
  m15: Bar[];
  m30: Bar[];
  h1: Bar[];
  spread: VenueSpread;
  blackout: boolean;
  lockSummary: string;
  sessionOpen: boolean;
  signalsEmittedToday: number;
  maxSignalsPerDay: number;
  duplicate: boolean;
  currentPrice: number | null;
  blockedByLevel: boolean;
  macroAlignment: number | null;
  sentimentAlignment: number | null;
}

export interface ScanOutput {
  verdict: Verdict;
  grade: Grade;
  reasonCodes: ReasonCode[];
  vetoes: ReasonCode[];
  technicalScore: number;
  finalScore: number;
  conflictPenalty: number;
  spread: VenueSpread;
  dataQuality: string[];
  lockSummary: string;
  stop: StopPlan | null;
  atr5m: number | null;
  headline: string;
}

function minBarsFor(tf: Tf): number {
  switch (tf) {
    case '5m': return 20;
    case '15m': return 50;
    case '30m': return 50;
    case '1h': return 200;
  }
}

export function stateFor(bars: Bar[], tf: Tf): TimeframeState {
  if (bars.length === 0) return EMPTY_TF(tf);
  const c = bars.map((b) => b.c);
  const e20 = ema(c, 20);
  const e50 = ema(c, 50);
  const e200 = ema(c, 200);
  const r = rsi(c, 14);
  const m = macd(c);
  const a = atr(bars, 14);
  const d = adx(bars, 14);
  const sw = swings(bars, 2);
  const lastIdx = bars.length - 1;
  const atrVals = Object.keys(a)
    .map((k) => a[Number(k)])
    .filter((v): v is number => v != null);

  const lo = lastSwingLow(sw, lastIdx);
  const hi = lastSwingHigh(sw, lastIdx);

  return {
    tf,
    // The close is an observed price, always defined. Gating it on EMA20
    // (as an earlier revision did) made the close disappear whenever the
    // series was shorter than the EMA period, which would blank out the very
    // price level a scanner needs most.
    close: c[c.length - 1],
    ema20: lastOf(e20),
    ema50: lastOf(e50),
    ema200: lastOf(e200),
    rsi14: lastOf(r),
    macdHistogram: lastOf(m.histogram),
    adx14: lastOf(d.adx),
    plusDi: lastOf(d.plusDi),
    minusDi: lastOf(d.minusDi),
    atr: lastOf(a),
    atrPercentile: atrPercentile(atrVals),
    swingLow: lo ? lo.price : null,
    swingHigh: hi ? hi.price : null,
    // Pattern flags stay false: inferring a structural pattern from indicator
    // state would be fabricating an observation the scanner did not make.
    hasPattern: false,
  };
}

export function scanMarket(
  input: ScanInput,
  thresholds: Thresholds = DEFAULT_THRESHOLDS,
  stopConfig: StopConfig = DEFAULT_STOP_CONFIG,
): ScanOutput {
  const quality: string[] = [];
  const usable = (bars: Bar[]): Bar[] => bars.filter((b) => b.closed);

  const series: Record<Tf, Bar[]> = {
    '5m': usable(input.m5),
    '15m': usable(input.m15),
    '30m': usable(input.m30),
    '1h': usable(input.h1),
  };

  const tooShort: string[] = [];
  (Object.keys(series) as Tf[]).forEach((tf) => {
    const need = minBarsFor(tf);
    if (series[tf].length < need) tooShort.push(`${tf}: ${series[tf].length}/${need} bars`);
  });
  if (tooShort.length > 0) quality.push(`insufficient history: ${tooShort.join(', ')}`);

  const degraded = (Object.keys(series) as Tf[])
    .filter((tf) => series[tf].length > 0 && series[tf].every((b) => b.degraded));
  if (degraded.length > 0) {
    quality.push(`degraded warm-up history on ${degraded.join(', ')} (proxy source; levels refused)`);
  }

  const base: Omit<ScanOutput, 'verdict' | 'grade' | 'reasonCodes' | 'vetoes' | 'technicalScore' | 'finalScore' | 'conflictPenalty' | 'stop' | 'headline'> = {
    spread: input.spread,
    lockSummary: input.lockSummary,
    atr5m: null,
  };

  // Indicators never initiate a trade: with no candidate direction the scan
  // refuses rather than picking the better-looking side.
  if (input.direction === null) {
    return {
      ...base,
      verdict: 'noTrade',
      grade: 'insufficient',
      reasonCodes: [],
      vetoes: ['v10ConfirmationLow'],
      technicalScore: 0,
      finalScore: 0,
      conflictPenalty: 0,
      dataQuality: ['no candidate direction: indicators never initiate a trade', ...quality],
      stop: null,
      headline: 'NO TRADE (no candidate direction)',
    };
  }

  const dir = input.direction;
  const states: Record<Tf, TimeframeState> = {
    '5m': stateFor(series['5m'], '5m'),
    '15m': stateFor(series['15m'], '15m'),
    '30m': stateFor(series['30m'], '30m'),
    '1h': stateFor(series['1h'], '1h'),
  };
  const atr5m = states['5m'].atr;

  const c = evaluateConfluence(
    {
      direction: dir,
      h1: states['1h'],
      m30: states['30m'],
      m15: states['15m'],
      m5: states['5m'],
      atr5m,
      macroAlignment: input.macroAlignment,
      sentimentAlignment: input.sentimentAlignment,
      spreadStatus: input.spread.status,
      blackout: input.blackout,
      dataStale: tooShort.length > 0,
      sessionOpen: input.sessionOpen,
      signalsEmittedToday: input.signalsEmittedToday,
      maxSignalsPerDay: input.maxSignalsPerDay,
      duplicate: input.duplicate,
      blockedByLevel: input.blockedByLevel,
    },
    thresholds,
  );

  let stop: StopPlan | null = null;
  let verdict = c.verdict;
  let vetoes = c.vetoed;

  if (c.verdict !== 'noTrade') {
    if (atr5m == null || atr5m <= 0) {
      stop = reject('ATR_UNAVAILABLE', input.spread.status, 'none');
    } else {
      const entry = input.currentPrice ?? states['5m'].close;
      if (entry == null || entry <= 0) {
        stop = reject('ENTRY_UNAVAILABLE', input.spread.status, 'none');
      } else if (degraded.includes('15m')) {
        // Never derive published levels from proxy history (§3.1).
        stop = reject('DEGRADED_HISTORY_NO_LEVELS', input.spread.status, 'none');
        quality.push('stop refused: degraded 15m history cannot produce levels');
      } else {
        const sw15 = swings(series['15m'], 2);
        const lastIdx = series['15m'].length - 1;
        const lo = lastSwingLow(sw15, lastIdx);
        const hi = lastSwingHigh(sw15, lastIdx);
        stop = buildStopPlan({
          direction: dir,
          entry,
          atr5m,
          swingLow: lo ? lo.price : null,
          swingHigh: hi ? hi.price : null,
          spreadStatus: input.spread.status,
          genuineSpread: input.spread.status === 'available' ? input.spread.value : null,
          config: stopConfig,
        });
      }
    }

    // Publishing entry without stop and targets would breach MGC R1.
    if (!stop || !stop.valid) {
      verdict = 'noTrade';
      vetoes = [...vetoes, 'v13BadStopDistance'];
      quality.push(`stop refused: ${stop?.rejectionReason ?? 'unknown'}`);
    }
  }

  const grade: Grade = verdict === 'noTrade' ? 'insufficient' : c.grade;
  const side = verdict === 'long' ? 'LONG' : verdict === 'short' ? 'SHORT' : 'NO TRADE';
  const headline =
    verdict === 'noTrade'
      ? `NO TRADE (${vetoes.join(', ')})`
      : stop && stop.valid
        ? `${side} ${grade === 'aPlus' ? 'A+' : grade.toUpperCase()} tech=${c.technicalScore} ` +
          `final=${c.finalScore.toFixed(1)} R:R=${stop.tp2R!.toFixed(2)}`
        : `${side} ${grade.toUpperCase()} tech=${c.technicalScore} NO LEVELS`;

  return {
    spread: input.spread,
    lockSummary: input.lockSummary,
    atr5m,
    verdict,
    grade,
    reasonCodes: c.reasonCodes,
    vetoes,
    technicalScore: c.technicalScore,
    finalScore: c.finalScore,
    conflictPenalty: c.conflictPenalty,
    dataQuality: quality,
    stop,
    headline,
  };
}

export { EMPTY_TF };