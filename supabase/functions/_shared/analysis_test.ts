/**
 * Cross-port equivalence tests: TypeScript analysis engine vs the Dart engine.
 *
 * The TS port is a mirror of src/xau_core/lib/analysis/*.dart, which is the
 * source of truth. These tests pin the behaviours that would otherwise drift
 * silently, and they use the same synthetic series shape as the Dart tests so
 * a divergence shows up as a concrete number mismatch.
 *
 * Run with Node's type stripping (Node 22.6+):  node analysis_test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  adx, atr, atrPercentile, bollinger, ema, macd, rsi, swings,
  lastSwingLow, lastSwingHigh, trueRange,
  evaluateConfluence, buildStopPlan, scanMarket,
  genuineSpread, unavailableSpread, stateFor,
  DEFAULT_THRESHOLDS, DEFAULT_STOP_CONFIG,
  type Bar, type TimeframeState, type Tf, type Side,
} from './analysis.ts';

/** Same construction as the Dart scanner test series. */
function series(
  tf: Tf,
  n = 260,
  start = 4000,
  driftPerBar = 0,
  amplitude = 6,
  period = 9,
  degraded = false,
): Bar[] {
  const mins = { '5m': 5, '15m': 15, '30m': 30, '1h': 60 }[tf];
  const base = Date.UTC(2026, 8, 1);
  const out: Bar[] = [];
  for (let i = 0; i < n; i++) {
    const level = start + driftPerBar * i;
    out.push({
      t: base + mins * 60_000 * i,
      o: level,
      h: level + amplitude * (0.5 + 0.5 * Math.sin(i / period)),
      l: level - amplitude * (0.5 + 0.5 * Math.sin(i / period)),
      c: level + amplitude * Math.sin(i / period),
      v: null,
      closed: true,
      degraded,
    });
  }
  return out;
}

function last(s: Record<number, number | null>): number | null {
  const keys = Object.keys(s).map(Number).sort((a, b) => b - a);
  for (const k of keys) {
    const v = s[k];
    if (v != null) return v;
  }
  return null;
}

// ---------------------------------------------------------------- indicators

/**
 * IndicatorSeries is a sparse object, so an undefined index reads as
 * `undefined`, not `null`. These assertions therefore check for
 * "not a number" rather than a specific falsy value -- the property that
 * actually matters is that an undefined indicator can never be mistaken for a
 * measured zero.
 */
function undef(v: number | null | undefined): boolean {
  return typeof v !== 'number';
}

test('ema seeds with an SMA then applies k = 2/(p+1)', () => {
  const r = ema([1, 2, 3, 4], 3);
  assert.ok(undef(r[0]));
  assert.ok(undef(r[1]));
  assert.equal(r[2], 2);
  assert.equal(r[3], 3);
});

test('ema stays flat on a constant series', () => {
  assert.ok(Math.abs(last(ema(new Array(10).fill(50), 5))! - 50) < 1e-9);
});

test('rsi pins at 100 on all gains and 0 on all losses, 50 on flat', () => {
  const up = Array.from({ length: 20 }, (_, i) => 100 + i);
  const down = Array.from({ length: 20 }, (_, i) => 100 - i);
  assert.equal(last(rsi(up))!, 100);
  assert.equal(last(rsi(down))!, 0);
  assert.equal(last(rsi(new Array(20).fill(100)))!, 50);
});

test('rsi is undefined below period + 1 samples', () => {
  assert.ok(undef(last(rsi([1, 2, 3]))));
});

test('macd histogram equals macd minus signal', () => {
  const prices = Array.from({ length: 120 }, (_, i) => 4000 + (i % 17) * 1.5);
  const m = macd(prices);
  const i = prices.length - 1;
  assert.ok(Math.abs(m.histogram[i]! - (m.macd[i]! - m.signal[i]!)) < 1e-9);
});

test('macd signal starts one defined-value period after warm-up', () => {
  const prices = Array.from({ length: 120 }, (_, i) => 4000 + i);
  const m = macd(prices);
  assert.ok(undef(m.macd[24]));
  assert.ok(!undef(m.macd[25]));
  assert.ok(undef(m.signal[32]));
  assert.ok(!undef(m.signal[33]));
});

test('atr equals a constant range and is undefined when too short', () => {
  const flat = Array.from({ length: 20 }, (_, i) => ({
    t: i, o: 4000, h: 4002, l: 3998, c: i % 2 === 0 ? 4002 : 3998,
    v: null, closed: true, degraded: false,
  }));
  assert.ok(Math.abs(last(atr(flat, 14))! - 4) < 1e-6);
  assert.ok(undef(last(atr(flat.slice(0, 10), 14))));
});

test('trueRange takes the widest of HL, HC, LC', () => {
  const prev = { t: 0, o: 4000, h: 4000, l: 4000, c: 4000, v: null, closed: true, degraded: false };
  const mk = (h: number, l: number) => ({ t: 5, o: 4000, h, l, c: 4000, v: null, closed: true, degraded: false });
  assert.equal(trueRange(prev, mk(4010, 4000)), 10);
  assert.equal(trueRange(prev, mk(4000, 3990)), 10);
});

test('adx is high in a clean trend and low in a choppy range', () => {
  const trend = Array.from({ length: 60 }, (_, i) => ({
    t: i, o: 4000 + i * 5, h: 4005 + i * 5, l: 3998 + i * 5, c: 4003 + i * 5,
    v: null, closed: true, degraded: false,
  }));
  const tr = adx(trend);
  assert.ok(tr.adx[59]! > 50);
  assert.ok(tr.plusDi[59]! > tr.minusDi[59]!);

  const chop = Array.from({ length: 60 }, (_, i) => ({
    t: i, o: 4000, h: 4002, l: 3998, c: 4000 + (i % 2 === 0 ? 1 : -1),
    v: null, closed: true, degraded: false,
  }));
  assert.ok(adx(chop).adx[59]! < 30);
});

test('bollinger bands straddle the middle and flat input has zero width', () => {
  const b = bollinger(Array.from({ length: 40 }, (_, i) => 4000 + (i % 7) * 2));
  assert.ok(b.upper[39]! > b.middle[39]!);
  assert.ok(b.lower[39]! < b.middle[39]!);
  const flat = bollinger(new Array(40).fill(4000));
  assert.equal(flat.bandwidth[39], 0);
});

test('swings find the peak and trough but never in the trailing lookback', () => {
  const highs = [4001, 4002, 4003, 4004, 4005, 4006, 4010, 4009, 4008, 4007, 4008, 4009, 4010];
  const lows = [3999, 3998, 3997, 3996, 3995, 3994, 3993, 3992, 3991, 3985, 3986, 3987, 3988];
  const bars: Bar[] = highs.map((h, i) => ({
    t: i, o: (h + lows[i]) / 2, h, l: lows[i], c: (h + lows[i]) / 2,
    v: null, closed: true, degraded: false,
  }));
  const s = swings(bars, 2);
  assert.ok(s.some((x) => x.isHigh && x.index === 6));
  assert.ok(s.some((x) => !x.isHigh && x.index === 9));
  assert.ok(s.every((x) => x.index <= bars.length - 1 - 2));
  // Lows descend strictly to the pivot at index 9, so there are no swing lows
  // before it at all: every interior bar has a lower neighbour on the right.
  assert.equal(lastSwingLow(s, 8), null);
  // The only pivot at or before index 6 is the swing high itself.
  assert.equal(lastSwingHigh(s, 6)?.index, 6);
  assert.equal(lastSwingHigh(s, 5), null);
});

test('atrPercentile refuses short history and ranks extremes correctly', () => {
  assert.ok(undef(atrPercentile([10, 11, 12])));
  assert.equal(atrPercentile([...Array.from({ length: 19 }, (_, i) => 10 + i), 99]), 100);
  assert.equal(atrPercentile([500, ...new Array(30).fill(10)], 10), 100);
});

// ---------------------------------------------------------------- confluence

function tfState(over: Partial<TimeframeState> = {}): TimeframeState {
  return {
    tf: '30m', close: 4050, ema20: 4040, ema50: 4030, ema200: 4000,
    rsi14: 60, macdHistogram: 1, adx14: 28, plusDi: 30, minusDi: 10,
    atr: 10, atrPercentile: 50, swingLow: 4035, swingHigh: 4048, hasPattern: true,
    ...over,
  };
}

function pullback(dir: Side): TimeframeState {
  return dir === 'long'
    ? tfState({ tf: '15m', close: 4035, ema20: 4040, ema50: 4030, ema200: 4000, rsi14: 58, macdHistogram: 0.5, adx14: 26, plusDi: 28, minusDi: 12, swingLow: 4025, swingHigh: 4050 })
    : tfState({ tf: '15m', close: 3965, ema20: 3960, ema50: 3970, ema200: 4000, rsi14: 42, macdHistogram: -0.5, adx14: 26, plusDi: 12, minusDi: 28, swingLow: 3950, swingHigh: 3975 });
}

function input(dir: Side = 'long', over: Record<string, unknown> = {}) {
  return {
    direction: dir,
    h1: tfState(),
    m30: tfState(),
    m15: pullback(dir),
    m5: tfState(),
    atr5m: 10,
    macroAlignment: null,
    sentimentAlignment: null,
    spreadStatus: 'unavailable' as const,
    blackout: false,
    dataStale: false,
    sessionOpen: true,
    signalsEmittedToday: 0,
    maxSignalsPerDay: 4,
    duplicate: false,
    blockedByLevel: false,
    ...over,
  };
}

test('a fully aligned long scores 12 and publishes', () => {
  const r = evaluateConfluence(input());
  assert.equal(r.technicalScore, 12);
  assert.equal(r.verdict, 'long');
  assert.equal(r.grade, 'aPlus');
});

test('the short side mirrors symmetrically', () => {
  const r = evaluateConfluence(input('short', { h1: tfState({ close: 3950, ema20: 3960, ema50: 3970, ema200: 4000, rsi14: 40, macdHistogram: -1, plusDi: 10, minusDi: 30, swingLow: 3952, swingHigh: 3965 }), m30: tfState({ close: 3950, ema20: 3960, ema50: 3970, ema200: 4000, rsi14: 40, macdHistogram: -1, plusDi: 10, minusDi: 30, swingLow: 3952, swingHigh: 3965 }), m5: tfState({ close: 3950, ema20: 3960, ema50: 3970, ema200: 4000, rsi14: 40, macdHistogram: -1, plusDi: 10, minusDi: 30, swingLow: 3952, swingHigh: 3965 }) }));
  assert.equal(r.technicalScore, 12);
  assert.equal(r.verdict, 'short');
});

test('short RSI reads its own mirrored preferred zone', () => {
  // Regression: a hard-coded bullish zone made the symmetric short unscoreable.
  const r = evaluateConfluence(input('short', {
    h1: tfState({ rsi14: 40, ema20: 3960, ema50: 3970, ema200: 4000, close: 3950, macdHistogram: -1, swingLow: 3952, swingHigh: 3965, plusDi: 10, minusDi: 30 }),
    m30: tfState({ close: 3950, ema20: 3960, ema50: 3970, ema200: 4000, rsi14: 40, macdHistogram: -1, swingLow: 3952, swingHigh: 3965, plusDi: 10, minusDi: 30 }),
    m5: tfState({ close: 3950, ema20: 3960, ema50: 3970, ema200: 4000, rsi14: 40, macdHistogram: -1, swingLow: 3952, swingHigh: 3965, plusDi: 10, minusDi: 30 }),
  }));
  assert.ok(r.reasonCodes.includes('h1RsiFavorable'));
});

test('every hard veto suppresses publication', () => {
  const cases: [Record<string, unknown>, string][] = [
    [{ blackout: true }, 'v1Blackout'],
    [{ dataStale: true }, 'v3DataStale'],
    [{ sessionOpen: false }, 'v8SessionClosed'],
    [{ signalsEmittedToday: 4 }, 'v7DailyLimit'],
    [{ duplicate: true }, 'v9Duplicate'],
    [{ blockedByLevel: true }, 'v5PoorRewardRisk'],
    [{ macroAlignment: -1 }, 'v6DirectionConflict'],
    [{ m5: tfState({ atrPercentile: 99 }) }, 'v4VolatilityExtreme'],
    [{ h1: tfState({ rsi14: 80 }) }, 'v14RsiExhausted'],
  ];
  for (const [over, code] of cases) {
    const r = evaluateConfluence(input('long', over));
    assert.equal(r.verdict, 'noTrade', `${code} should veto`);
    assert.ok(r.vetoed.includes(code as never), `expected ${code}, got ${r.vetoed}`);
  }
});

test('unavailable spread is UNEVALUATED context, never a veto', () => {
  const r = evaluateConfluence(input());
  assert.ok(r.reasonCodes.includes('v2SpreadUnevaluated'));
  assert.ok(!r.vetoed.includes('v2SpreadUnevaluated'));
  assert.equal(r.verdict, 'long');
});

test('an available spread adds no data-quality note', () => {
  const r = evaluateConfluence(input('long', { spreadStatus: 'available' }));
  assert.ok(!r.reasonCodes.includes('v2SpreadUnevaluated'));
});

test('slow sentiment lowers confidence but never flips the trade', () => {
  const r = evaluateConfluence(input('long', { sentimentAlignment: -1 }));
  assert.equal(r.verdict, 'long');
  assert.ok(r.finalScore < 12);
  assert.equal(r.conflictPenalty, 1);
});

test('supporting macro lifts only the final score', () => {
  const base = evaluateConfluence(input());
  const sup = evaluateConfluence(input('long', { macroAlignment: 1 }));
  assert.equal(sup.technicalScore, base.technicalScore);
  assert.ok(Math.abs(sup.finalScore - (base.finalScore + 2)) < 1e-9);
});

// ---------------------------------------------------------------- stop plan

test('long stop sits below the swing plus a 0.20 ATR buffer', () => {
  const p = buildStopPlan({ direction: 'long', entry: 4000, atr5m: 10, swingLow: 3990, spreadStatus: 'unavailable' });
  assert.ok(p.valid);
  assert.equal(p.stopLoss, 3988);
  assert.equal(p.bufferSource, '0.20*ATR');
});

test('short stop mirrors above the swing', () => {
  const p = buildStopPlan({ direction: 'short', entry: 4000, atr5m: 10, swingHigh: 4010, spreadStatus: 'unavailable' });
  assert.ok(p.valid);
  assert.equal(p.stopLoss, 4012);
});

test('a missing confirmed swing refuses rather than guessing', () => {
  assert.equal(buildStopPlan({ direction: 'long', entry: 4000, atr5m: 10, spreadStatus: 'unavailable' }).rejectionReason, 'NO_CONFIRMED_SWING_LOW');
  assert.equal(buildStopPlan({ direction: 'short', entry: 4000, atr5m: 10, spreadStatus: 'unavailable' }).rejectionReason, 'NO_CONFIRMED_SWING_HIGH');
});

test('an over-wide structural stop is rejected, never widened', () => {
  const p = buildStopPlan({ direction: 'long', entry: 4000, atr5m: 10, swingLow: 3970, spreadStatus: 'unavailable' });
  assert.ok(!p.valid);
  assert.equal(p.rejectionReason, 'STRUCTURAL_STOP_TOO_WIDE');
});

test('an over-tight stop widens to the 0.8 ATR floor', () => {
  const p = buildStopPlan({ direction: 'long', entry: 4000, atr5m: 10, swingLow: 3999.5, spreadStatus: 'unavailable' });
  assert.ok(p.valid);
  assert.ok(Math.abs(p.riskDistanceAtr! - 0.8) < 1e-9);
});

test('a supplied spread is ignored while status is unavailable', () => {
  // Regression guard for the ratified option (a) rule.
  const p = buildStopPlan({
    direction: 'long', entry: 4000, atr5m: 10, swingLow: 3990,
    spreadStatus: 'unavailable', genuineSpread: 5,
  });
  assert.equal(p.bufferSource, '0.20*ATR');
  assert.equal(p.stopLoss, 3988);
});

test('a genuine venue spread widens the buffer only when larger', () => {
  const wider = buildStopPlan({
    direction: 'long', entry: 4000, atr5m: 10, swingLow: 3992,
    spreadStatus: 'available', genuineSpread: 5,
  });
  assert.ok(wider.valid);
  assert.equal(wider.bufferSource, 'max(0.20*ATR, spread*2)');
  assert.equal(wider.stopLoss, 3982);

  const narrower = buildStopPlan({
    direction: 'long', entry: 4000, atr5m: 50, swingLow: 3960,
    spreadStatus: 'available', genuineSpread: 1,
  });
  assert.equal(narrower.stopLoss, 3950);
});

test('targets are exact R multiples and satisfy the 1.8R floor', () => {
  const p = buildStopPlan({ direction: 'long', entry: 4000, atr5m: 10, swingLow: 3990, spreadStatus: 'unavailable' });
  assert.ok(Math.abs(p.tp1! - 4012) < 1e-9);
  assert.ok(Math.abs(p.tp2! - 4024) < 1e-9);
  assert.ok(Math.abs(p.tp3! - 4036) < 1e-9);
  assert.ok(p.tp2R! >= DEFAULT_THRESHOLDS.tp2FloorR);
});

test('a short plan puts targets below entry', () => {
  const p = buildStopPlan({ direction: 'short', entry: 4000, atr5m: 10, swingHigh: 4010, spreadStatus: 'unavailable' });
  assert.ok(p.tp1! < p.entry);
  assert.ok(p.tp3! < p.tp1!);
});

// ------------------------------------------------------------------- spread

test('a crossed quote yields no spread rather than a negative one', () => {
  const s = genuineSpread(4145, 4140, 'bad');
  assert.equal(s.status, 'unavailable');
  assert.equal(s.value, null);
  assert.equal(s.source, 'NONE');
});

test('a genuine quote measures the venue spread', () => {
  const s = genuineSpread(4142.45, 4143.28, 'oanda-practice');
  assert.equal(s.status, 'available');
  assert.ok(Math.abs(s.value! - 0.83) < 1e-9);
  assert.equal(s.source, 'oanda-practice');
});

test('unavailable spread is a distinct, explicit state', () => {
  const s = unavailableSpread();
  assert.equal(s.status, 'unavailable');
  assert.equal(s.value, null);
  assert.equal(s.source, 'NONE');
});

// ------------------------------------------------------------------ scanner

function scan(over: Record<string, unknown> = {}) {
  return scanMarket({
    direction: 'long',
    m5: series('5m', 260, 4000, 0.35),
    m15: series('15m', 260, 4000, 0.12),
    m30: series('30m', 260, 4000, 0.06),
    h1: series('1h', 260, 4000, 0.03),
    spread: unavailableSpread(),
    blackout: false,
    lockSummary: 'N/A',
    sessionOpen: true,
    signalsEmittedToday: 0,
    maxSignalsPerDay: 4,
    duplicate: false,
    currentPrice: null,
    blockedByLevel: false,
    macroAlignment: null,
    sentimentAlignment: null,
    ...over,
  } as never);
}

test('a null direction yields NO TRADE and states it declined to choose', () => {
  const r = scan({ direction: null });
  assert.equal(r.verdict, 'noTrade');
  assert.ok(r.dataQuality.join(' ').includes('no candidate direction'));
});

test('short 1H history vetoes and reports the shortfall', () => {
  const r = scan({ h1: series('1h', 30) });
  assert.equal(r.verdict, 'noTrade');
  assert.ok(r.vetoes.includes('v3DataStale'));
  assert.ok(r.dataQuality.join(' ').includes('1h: 30/200 bars'));
});

test('sufficient history clears the sufficiency note', () => {
  const r = scan();
  assert.equal(r.dataQuality.filter((d) => d.includes('insufficient history')).length, 0);
});

test('open bars are excluded from the scan', () => {
  const bars = series('1h', 260);
  const opened = [...bars.slice(0, 259), { ...bars[259], closed: false }];
  const r = scan({ h1: opened });
  assert.ok(r.dataQuality.join(' ').includes('1h: 259/200') === false);
});

test('degraded proxy history refuses to produce levels', () => {
  const r = scan({ m15: series('15m', 260, 4000, 0.12, 6, 9, true), currentPrice: 4100 });
  if (r.verdict !== 'noTrade') throw new Error(`published levels from proxy history: ${r.headline}`);
  assert.ok(r.dataQuality.join(' ').includes('degraded'));
});

test('a trade never ships without stop and three targets', () => {
  const r = scan({ currentPrice: 4100 });
  if (r.verdict !== 'noTrade') {
    assert.ok(r.stop);
    assert.ok(r.stop!.valid);
    assert.ok(r.stop!.riskDistance! > 0);
    assert.ok(r.stop!.tp2R! >= 1.8);
    assert.ok(r.stop!.riskDistanceAtr! >= 0.8 && r.stop!.riskDistanceAtr! <= 1.8);
  }
});

test('identical inputs produce identical output', () => {
  assert.equal(scan({ currentPrice: 4100 }).headline, scan({ currentPrice: 4100 }).headline);
});

test('the headline never implies probability', () => {
  const h = scan({ currentPrice: 4100 }).headline.toLowerCase();
  for (const banned of ['%', 'chance', 'probabil', 'guarantee', 'sure']) {
    assert.ok(!h.includes(banned), `headline leaked "${banned}": ${h}`);
  }
});

test('stateFor keeps undefined indicators undefined rather than zero', () => {
  const short = stateFor(series('1h', 10), '1h');
  assert.ok(undef(short.ema200), 'EMA200 undefined below 200 samples');
  assert.ok(undef(short.adx14), 'ADX undefined below 29 samples');
  assert.ok(undef(short.rsi14), 'RSI14 undefined below 15 samples');
  // The close is an observed price: always present, even on a short series.
  assert.ok(!undef(short.close));

  const long = stateFor(series('1h', 260), '1h');
  assert.ok(!undef(long.ema200), 'EMA200 defined with sufficient history');
  assert.ok(!undef(long.adx14));
  assert.ok(!undef(long.rsi14));
});

test('stateFor does not fabricate candle patterns', () => {
  assert.equal(stateFor(series('15m', 260), '15m').hasPattern, false);
});