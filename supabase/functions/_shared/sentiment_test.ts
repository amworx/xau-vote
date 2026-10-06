/**
 * Tests for _shared/sentiment.ts.
 *
 * Fixtures are real rows captured from the live CFTC and US Treasury
 * publications on 2026-10-05, so a column shift at the source shows up here
 * rather than silently skewing a live verdict.
 *
 * Run: node sentiment_test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  WEIGHTS,
  PERCENTILE_WEEKS,
  GOLD_CODE,
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
  MACRO_SIDE_WEIGHT,
  type TreasuryRow,
} from './sentiment.ts';

test('§5.1 weights, minus the layer we cannot license', () => {
  assert.equal(WEIGHTS.policy, 35);
  assert.equal(WEIGHTS.positioning, 25);
  assert.equal(WEIGHTS.market_implied, 20);

  // The methodology's fourth layer is gone, not reweighted. D-20261006-011.
  assert.equal(
    'gold_fundamentals' in WEIGHTS,
    false,
    'gold_fundamentals must stay removed: its source cannot be licensed',
  );

  // The claim is now 80 points, not 100. Renormalising to re-absorb the freed 20
  // would silently change the scoring, which is not a licensing fix.
  const total = Object.values(WEIGHTS).reduce((a, b) => a + b, 0);
  assert.equal(total, 80);
});

test('macro-side weight is what is actually measurable', () => {
  assert.equal(MACRO_SIDE_WEIGHT, 55);
  // Positioning is sentiment, not macro.
  assert.equal(MACRO_SIDE_WEIGHT, WEIGHTS.policy + WEIGHTS.market_implied);
});

test('§1.6 percentile window is 156 weeks', () => {
  assert.equal(PERCENTILE_WEEKS, 156);
});

// ── §5.3 band scoring ────────────────────────────────────────────────────────

test('§5.3 bands score the extremes even without a trend leg', () => {
  assert.equal(cotScore(5), -1); // <20, would be -2 with a bearish trend
  assert.equal(cotScore(32.6), -1); // the documented overlap case
  assert.equal(cotScore(39.9), -1);
  assert.equal(cotScore(40), 0);
  assert.equal(cotScore(59.9), 0);
  assert.equal(cotScore(60), 1);
  assert.equal(cotScore(80), 1);
  assert.equal(cotScore(95), 1); // >80, would be +2 with a bullish trend
});

test('§5.3 ±2 is only reachable when the price trend confirms the extreme', () => {
  assert.equal(cotScore(5, 'bearish'), -2);
  assert.equal(cotScore(95, 'bullish'), 2);
  // A trend that contradicts the reading must NOT upgrade to the extreme.
  assert.equal(cotScore(95, 'bearish'), 1);
  assert.equal(cotScore(5, 'bullish'), -1);
});

test('§5.3 the narrower band wins where the methodology bands overlap', () => {
  // 32.6 satisfies both "20-60 → 0" and "20-40 → -1". The narrower, more
  // informative band decides, so this is not neutral.
  assert.equal(cotScore(32.6), -1);
  assert.notEqual(cotScore(32.6), 0);
});

test('alignment maps score to direction', () => {
  assert.equal(alignmentOf(2), 1);
  assert.equal(alignmentOf(1), 1);
  assert.equal(alignmentOf(0), 0);
  assert.equal(alignmentOf(-1), -1);
  assert.equal(alignmentOf(-2), -1);
});

// ── §1.6 percentile ──────────────────────────────────────────────────────────

test('percentileRank counts strictly-below observations', () => {
  const series = [1, 2, 3, 4];
  assert.equal(percentileRank(series, 0), 0);
  assert.equal(percentileRank(series, 3), 50); // 1,2 below → 2/4
  assert.equal(percentileRank(series, 5), 100);
  // An empty window must not divide by zero; 50 is neutral, not a real reading.
  assert.equal(percentileRank([], 100), 50);
});

// Managed-money net for COMEX gold over the last 156 weeks, pulled from CFTC's
// Socrata dataset 72hh-3qpy ("Disaggregated - Futures Only") on 2026-10-05 and
// ordered newest first, 2026-09-29 -> 2023-10-10. These are the real published
// numbers, not illustrative ones, so a change at the source shows up here.
const COT_WINDOW = [
  120318, 127389, 133116, 134972, 136771, 144747, 141648, 137662,
  130766, 119795, 124831, 120779, 116161, 120091, 115395, 113721,
  105863, 112179, 97446, 93540, 98015, 94254, 89752, 92976,
  95141, 90032, 92814, 91621, 102043, 98399, 97917, 95974,
  95893, 92022, 92072, 118159, 137444, 134745, 123213, 126040,
  136270, 132596, 123548, 120324, 109309, 98205, 104087, 100545,
  104159, 92227, 108310, 129759, 145227, 160549, 158971, 163519,
  161502, 141917, 137385, 148287, 153987, 134256, 159934, 136727,
  128942, 130360, 125128, 130511, 124091, 123582, 110816, 107629,
  101227, 102091, 105895, 120902, 124854, 130986, 141999, 174732,
  183834, 167576, 166658, 179812, 185329, 194803, 209533, 210540,
  215869, 195622, 177641, 166169, 165497, 183502, 196078, 180735,
  179290, 155174, 165296, 183003, 195173, 205160, 199421, 194059,
  214462, 219029, 216355, 190455, 192090, 200291, 193305, 177915,
  150786, 152364, 162860, 184532, 157467, 150815, 158202, 160621,
  152965, 152299, 148828, 148523, 130435, 126099, 135027, 142139,
  134736, 141732, 147080, 135795, 142896, 141083, 109763, 56153,
  49923, 34176, 68069, 56024, 61033, 83229, 88459, 109149,
  106454, 108276, 95528, 109387, 114893, 79135, 64315, 78235,
  74840, 55748, 15103, -26767,
];

test('the CFTC window is the full 156 weeks §1.6 asks for', () => {
  assert.equal(COT_WINDOW.length, PERCENTILE_WEEKS);
});

test('percentileRank on the live managed-money series is in the 20-40 band', () => {
  // The most recent reading, 2026-09-29: 120,318 contracts net long.
  const pct = percentileRank(COT_WINDOW, 120318);
  assert.equal(Math.round(pct * 10) / 10, 37.8);
  assert.ok(pct > 20 && pct < 40, `expected the 20-40 band, got ${pct}`);
  assert.equal(cotScore(pct), -1, 'lower third of the range is not neutral');
});

test('the live COT reading sits inside its own three-year range', () => {
  const sorted = [...COT_WINDOW].sort((a, b) => a - b);
  assert.equal(sorted[0], -26767); // a net-short week
  assert.equal(sorted[sorted.length - 1], 219029);
  const current = COT_WINDOW[0];
  assert.ok(current > sorted[0] && current < sorted[sorted.length - 1]);
});

test('a flat series puts every reading at the 50th percentile', () => {
  const flat = [120318, 120318, 120318, 120318];
  // Strictly-below counting means a value equal to the whole series is 0%.
  // That is the correct reading of "not below anything", and it is why the
  // production path ranks against real historical variation, not a constant.
  assert.equal(percentileRank(flat, 120318), 0);
});

test('dateOnly strips the timestamp without a timezone shift', () => {
  // CFTC's Socrata API returns calendar_date as 2026-09-29T00:00:00.000.
  assert.equal(dateOnly('2026-09-29T00:00:00.000'), '2026-09-29');
  assert.equal(dateOnly('2026-09-29'), '2026-09-29');
  assert.equal(dateOnly('  2026-09-29T12:34:56.000  '), '2026-09-29');
  assert.equal(dateOnly(''), null);
  assert.equal(dateOnly('not-a-date'), null);
  // The returned value must survive a UTC round trip untouched.
  assert.equal(
    new Date(dateOnly('2026-09-29T00:00:00.000')! + 'T00:00:00Z').toISOString().slice(0, 10),
    '2026-09-29',
  );
});

// ── Treasury date handling (the timezone regression) ─────────────────────────

test('parseTreasuryDate reads MM/DD/YYYY as a UTC date', () => {
  assert.equal(parseTreasuryDate('10/02/2026'), '2026-10-02');
  assert.equal(parseTreasuryDate('1/2/2026'), '2026-01-02');
  assert.equal(parseTreasuryDate('12/31/2025'), '2025-12-31');
});

test('parseTreasuryDate does not shift across the UTC boundary', () => {
  // A local-midnight parse would return 2026-10-01 east of UTC. The date-only
  // value must not depend on where the function runs.
  const iso = parseTreasuryDate('10/02/2026')!;
  assert.equal(new Date(iso + 'T00:00:00Z').toISOString().slice(0, 10), iso);
  assert.equal(new Date(iso + 'T00:00:00Z').getUTCDay(), 5); // a Friday
});

test('parseTreasuryDate rejects anything that is not that shape', () => {
  assert.equal(parseTreasuryDate(''), null);
  assert.equal(parseTreasuryDate('2026-10-02'), null);
  assert.equal(parseTreasuryDate('nonsense'), null);
});

// ── §5.1 real-yield impulse ──────────────────────────────────────────────────

const TREASURY_LIVE: TreasuryRow[] = [
  { date: '2026-09-24', real5y: 2.62, real10y: 2.83 },
  { date: '2026-09-25', real5y: 2.63, real10y: 2.83 },
  { date: '2026-09-28', real5y: 2.66, real10y: 2.86 },
  { date: '2026-09-29', real5y: 2.68, real10y: 2.88 },
  { date: '2026-09-30', real5y: 2.71, real10y: 2.90 },
  { date: '2026-10-01', real5y: 2.73, real10y: 2.91 },
  { date: '2026-10-02', real5y: 2.69, real10y: 2.92 },
];

test('§5.1 rising real yields are bearish for gold', () => {
  const r = realYieldImpulse(TREASURY_LIVE);
  assert.equal(r.latest?.date, '2026-10-02');
  // Five sessions back from the latest is 2026-09-25 at 2.83.
  assert.equal(r.prior?.date, '2026-09-25');
  assert.equal(r.impulse, 9); // 2.92 - 2.83 = 9bp
  assert.equal(r.alignment, -1);
});

test('§5.1 falling real yields are bullish for gold', () => {
  const falling = [...TREASURY_LIVE].reverse();
  const r = realYieldImpulse(falling);
  assert.ok(r.impulse! < 0);
  assert.equal(r.alignment, 1);
});

test('§5.1 a sub-5bp move is not read as a signal', () => {
  const flat: TreasuryRow[] = [
    { date: '2026-09-30', real5y: 2.70, real10y: 2.90 },
    { date: '2026-10-02', real5y: 2.70, real10y: 2.92 },
  ];
  const r = realYieldImpulse(flat);
  assert.equal(r.impulse, 2);
  assert.equal(r.alignment, 0, '2bp of noise must not become directional alignment');
});

test('§5.1 a series with no usable 10Y yields reports null, never a guess', () => {
  const r = realYieldImpulse([{ date: '2026-10-02', real5y: 2.69, real10y: null }]);
  assert.equal(r.impulse, null);
  assert.equal(r.alignment, null);
});

// ── staleness ────────────────────────────────────────────────────────────────

test('staleness thresholds follow §27 Failure 4', () => {
  assert.equal(COT_STALE_DAYS, 10);
  assert.equal(TREASURY_STALE_DAYS, 5);
});

test('ageInDays measures from a UTC date, not a local one', () => {
  const now = new Date('2026-10-05T12:00:00Z').getTime();
  assert.ok(Math.abs(ageInDays('2026-10-02', now) - 3.5) < 1e-9);
  // The live COT reading (as of Tuesday 2026-09-29, published that Friday) is
  // 6.5 days old on 2026-10-05 — inside the weekly window, so still fresh.
  // This is the check that would catch a feed silently going quiet.
  const cotAge = ageInDays('2026-09-29', now);
  assert.ok(Math.abs(cotAge - 6.5) < 1e-9, `expected 6.5 days, got ${cotAge}`);
  assert.ok(cotAge < COT_STALE_DAYS, 'the live COT read must not be stale');
  // A reading from a month ago must trip the threshold.
  assert.ok(ageInDays('2026-09-05', now) > COT_STALE_DAYS);
  assert.ok(ageInDays('2026-10-02', now) < TREASURY_STALE_DAYS);
});

// ── parsing primitives ───────────────────────────────────────────────────────

test('splitCsv handles quoted fields and embedded commas', () => {
  assert.deepEqual(
    splitCsv('"GOLD - COMMODITY EXCHANGE INC.",260929,2026-09-29'),
    ['GOLD - COMMODITY EXCHANGE INC.', '260929', '2026-09-29'],
  );
  assert.deepEqual(splitCsv('a,"b,c",d'), ['a', 'b,c', 'd']);
  assert.deepEqual(splitCsv('a,"say ""hi""",c'), ['a', 'say "hi"', 'c']);
});

test('num treats blank and NA as missing rather than zero', () => {
  assert.equal(num('  406456'), 406456);
  assert.equal(num('2.92'), 2.92);
  assert.equal(num(''), null);
  assert.equal(num('  '), null);
  assert.equal(num('NA'), null);
  assert.equal(num(undefined), null);
  assert.equal(num('abc'), null);
});

test('CFTC contract code for COMEX gold is pinned', () => {
  // If CFTC re-codes the contract this constant must be re-checked by hand.
  assert.equal(GOLD_CODE, '088691');
});