/**
 * Golden tests for the TS engine port (_shared/engine.ts).
 *
 * Vectors in golden/*.json mirror the Dart test expectations in
 * src/xau_core/test (the source of truth). Run with Node's built-in
 * type stripping (Node 22.6+):  node engine_test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  clusterRanges,
  clusterValues,
  clusterTakeProfits,
  strengthBand,
  riskReward,
  freshnessBand,
  transition,
  isBlackout,
  ENTRY_TOLERANCE,
  SL_TOLERANCE,
  TP_TOLERANCE,
} from './engine.ts';

const root = dirname(fileURLToPath(import.meta.url));
const golden = (name: string) => JSON.parse(readFileSync(join(root, 'golden', name), 'utf8'));
const approx = (a: number, b: number, eps = 1e-9): boolean => Math.abs(a - b) < eps;

test('spec §6 A/B/C LONG cluster', () => {
  const g = golden('cluster-long.json');
  const entry = clusterRanges(g.entryZones, ENTRY_TOLERANCE);
  assert.deepEqual(entry.consensus, g.expectedEntry);
  assert.deepEqual(entry.outliers, []);
  const sl = clusterValues(g.stopLosses, SL_TOLERANCE);
  assert.ok(approx(sl.consensus, g.expectedSlConsensus));
  assert.deepEqual(sl.outliers, g.expectedSlOutliers);
  const tps = clusterTakeProfits(
    Object.fromEntries(Object.entries(g.takeProfits).map(([k, v]) => [Number(k), v as number[]])),
    TP_TOLERANCE,
  );
  assert.ok(approx(tps[1].consensus, g.expectedTp1));
  assert.ok(approx(tps[2].consensus, g.expectedTp2));
});

test('spec §9 SL outlier rejection', () => {
  const g = golden('cluster-sl-outlier.json');
  const sl = clusterValues(g.stopLosses, SL_TOLERANCE);
  assert.ok(approx(sl.consensus, g.expectedSlConsensus));
  assert.deepEqual(sl.outliers, g.expectedSlOutliers);
  assert.deepEqual([sl.low, sl.high], g.expectedInlierSpan);
});

test('spec §11 R:R exact numbers', () => {
  const g = golden('scoring-lifecycle-guard.json').riskReward;
  const rr = riskReward(g.entry, g.stopLoss, g.takeProfits);
  assert.equal(rr.risk, g.expectedRisk);
  assert.deepEqual(rr.rewards, g.expectedRewards);
  assert.equal(rr.ratios.length, g.expectedRatios.length);
  rr.ratios.forEach((r: number, i: number) => assert.ok(approx(r, g.expectedRatios[i])));
});

test('spec §7 strength bands at every boundary', () => {
  const g = golden('scoring-lifecycle-guard.json');
  for (const b of g.bands) assert.equal(strengthBand(b.score), b.band, `score ${b.score}`);
});

test('spec §15 freshness bands at every boundary', () => {
  const g = golden('scoring-lifecycle-guard.json');
  for (const f of g.freshness) assert.equal(freshnessBand(f.ageMinutes), f.band, `age ${f.ageMinutes}`);
});

test('spec §14 legal and illegal transitions', () => {
  const g = golden('scoring-lifecycle-guard.json');
  for (const [from, to] of g.legalTransitions) assert.equal(transition(from, to), to);
  for (const [from, to] of g.illegalTransitions) assert.throws(() => transition(from, to));
});

test('event-guard blackout edges', () => {
  const g = golden('scoring-lifecycle-guard.json').guard;
  for (const c of g.cases) {
    assert.equal(isBlackout(c.nowMs, g.eventStartMs, c.impact), c.blackout, JSON.stringify(c));
  }
});
