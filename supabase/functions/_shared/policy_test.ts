/**
 * Tests for _shared/policy.ts (methodology §5.2).
 *
 * Fixtures are verbatim excerpts from the real FOMC statements of 2026-07-29
 * and 2026-09-16, captured 2026-10-05, so a change in how the Fed words its
 * decision sentence shows up here rather than silently scoring 0.
 *
 * Run: node policy_test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  POLICY_WEIGHT,
  POLICY_DECAY_DAYS,
  POLICY_STALE_DAYS,
  policyScoreFor,
  policyDecay,
  stripHtml,
  parsePercentToken,
  parseTargetRange,
  parseFomcAction,
  parseDissents,
  parseFomcStatement,
  statementDateFromUrl,
  latestStatementPaths,
  targetChangeBp,
} from './policy.ts';

// Verbatim decision sentences.
const JULY = 'In support of its goals, the Committee decided to maintain the target range for the federal funds rate at 3-1/2 to 3-3/4 percent, in support of the Federal Reserve&#8217;s dual mandate.';
const SEPT = 'In support of its goals, the Committee decided to raise the target range for the federal funds rate by 1/4 percentage point to 3-3/4 to 4 percent, in support of the Federal Reserve&#8217;s dual mandate.';
const DISSENT = 'Voting against the monetary policy action were Beth M. Hammack and Jeffrey R. Schmidt.';

test('§5.1 the policy layer is the largest of the four', () => {
  assert.equal(POLICY_WEIGHT, 35);
});

test('§5.2 score table', () => {
  assert.equal(policyScoreFor('raise'), -2);
  assert.equal(policyScoreFor('lower'), 2);
  assert.equal(policyScoreFor('maintain'), 0);
  // An unreadable decision is neutral/uncertain, never a guess.
  assert.equal(policyScoreFor('unknown'), 0);
});

test('the decision verb is read from the statement', () => {
  assert.equal(parseFomcAction(JULY), 'maintain');
  assert.equal(parseFomcAction(SEPT), 'raise');
  assert.equal(parseFomcAction('the Committee decided to lower the target range'), 'lower');
  assert.equal(parseFomcAction('the Committee decided to reduce the target range'), 'lower');
  assert.equal(parseFomcAction('no decision sentence here'), 'unknown');
});

test('mixed fractions are not read as subtraction', () => {
  // The hyphen in "3-3/4" belongs to the mixed number.
  assert.equal(parsePercentToken('3-3/4'), 3.75);
  assert.equal(parsePercentToken('3-1/2'), 3.5);
  assert.equal(parsePercentToken('4-1/4'), 4.25);
  assert.equal(parsePercentToken('4'), 4);
  assert.equal(parsePercentToken('5-1/2'), 5.5);
  assert.equal(parsePercentToken('nonsense'), null);
  assert.equal(parsePercentToken('3-1/0'), null, 'zero denominator is not a number');
});

test('the target range is read from the decision sentence', () => {
  assert.deepEqual(parseTargetRange(JULY), { low: 3.5, high: 3.75 });
  assert.deepEqual(parseTargetRange(SEPT), { low: 3.75, high: 4 });
  assert.equal(parseTargetRange('no numbers here'), null);
});

test('dissents are read when disclosed, and null when there were none', () => {
  assert.deepEqual(parseDissents(DISSENT), ['Beth M. Hammack', 'Jeffrey R. Schmidt']);
  assert.equal(parseDissents(SEPT), null, 'no dissents is an observation, not a gap');
});

test('stripHtml keeps the decision sentence and drops the chrome', () => {
  const html = `<html><head><style>.x{color:red}</style></head><body><p>${SEPT}</p></body></html>`;
  const text = stripHtml(html);
  assert.ok(text.includes('decided to raise the target range'));
  assert.ok(!text.includes('color:red'));
  assert.ok(!text.includes('<p>'));
});

test('a full statement parses into the §5.2 fields', () => {
  const s = parseFomcStatement(`<html><body><p>${SEPT}</p></body></html>`, '2026-09-16');
  assert.equal(s.action, 'raise');
  assert.equal(s.targetLow, 3.75);
  assert.equal(s.targetHigh, 4);
  assert.equal(s.dissents, null);
  assert.ok(s.decisionSentence?.includes('raise'));
});

test('the July statement is a hold with a disclosed dissent', () => {
  const s = parseFomcStatement(
    `<html><body><p>${JULY}</p><p>${DISSENT}</p></body></html>`,
    '2026-07-29',
  );
  assert.equal(s.action, 'maintain');
  assert.equal(s.targetLow, 3.5);
  assert.equal(s.targetHigh, 3.75);
  assert.equal(s.dissents?.length, 2);
  assert.deepEqual(s.dissents, ['Beth M. Hammack', 'Jeffrey R. Schmidt']);
});

test('a middle initial does not truncate a dissenter name', () => {
  // "Beth M. Hammack" has a period in the middle of the name; capturing to the
  // next period would yield "Beth M".
  assert.deepEqual(parseDissents(DISSENT), ['Beth M. Hammack', 'Jeffrey R. Schmidt']);
  assert.deepEqual(parseDissents('Voting against the action were Janet L. Yellen.'), [
    'Janet L. Yellen',
  ]);
  assert.deepEqual(
    parseDissents('Voting against the action were John C. Williams and Mary E. Daly.'),
    ['John C. Williams', 'Mary E. Daly'],
  );
});

test('a real sentence end still stops the window', () => {
  const withNext = `${DISSENT} The Committee then reviewed economic conditions.`;
  assert.deepEqual(parseDissents(withNext), ['Beth M. Hammack', 'Jeffrey R. Schmidt']);
});

test('the statement date comes from the URL, not the body', () => {
  assert.equal(
    statementDateFromUrl('/newsevents/pressreleases/monetary20260916a.htm'),
    '2026-09-16',
  );
  assert.equal(statementDateFromUrl('/newsevents/press/monetary.htm'), null);
});

test('the calendar yields the newest statements, ignoring a1 variants', () => {
  // Shaped like the real fomccalendars.htm, including the trailing-digit
  // implementation notes that are NOT the decision statement.
  const html = `
    <a href="/newsevents/pressreleases/monetary20260429a.htm">Apr</a>
    <a href="/newsevents/pressreleases/monetary20260429a1.htm">notes</a>
    <a href="/newsevents/pressreleases/monetary20260916a.htm">Sep</a>
    <a href="/newsevents/pressreleases/monetary20260916a1.htm">notes</a>
    <a href="/newsevents/pressreleases/monetary20260729a.htm">Jul</a>`;
  const latest = latestStatementPaths(html, 3);
  assert.equal(latest.length, 3);
  assert.deepEqual(
    latest.map((s) => s.date),
    ['2026-09-16', '2026-07-29', '2026-04-29'],
  );
  assert.ok(!latest.some((s) => s.url.endsWith('a1')));
});

test('the target range change is measured against the previous statement', () => {
  const jul = parseFomcStatement(`<p>${JULY}</p>`, '2026-07-29');
  const sep = parseFomcStatement(`<p>${SEPT}</p>`, '2026-09-16');
  // Midpoint 3.625 -> 3.875 = +25bp, i.e. a hike.
  assert.equal(targetChangeBp(jul, sep), 25);
  assert.equal(targetChangeBp(sep, jul), -25);
});

test('a change cannot be asserted when a level is missing', () => {
  const unknown = { action: 'unknown' as const, targetLow: null, targetHigh: null, dissents: null, decisionSentence: null };
  const sep = parseFomcStatement(`<p>${SEPT}</p>`, '2026-09-16');
  assert.equal(targetChangeBp(unknown, sep), null);
});

test('§5.2 freshness decay', () => {
  // 2026-09-16 hike read on 2026-10-05: 19 days.
  const raw = policyScoreFor('raise'); // -2
  const effective = policyDecay(raw, 19);
  assert.ok(effective < 0, 'decay must preserve the sign');
  assert.ok(Math.abs(effective) < 2, 'a 19-day-old hike is worth less than -2');
  assert.equal(effective, -1.06);
  // An event from today is essentially undecayed.
  assert.equal(policyDecay(-2, 0), -2);
  // Decay is monotonic and never overshoots past zero.
  assert.ok(policyDecay(-2, 60) > policyDecay(-2, 30));
  assert.ok(Math.abs(policyDecay(-2, 1000)) < 0.01);
  // A clock skew that yields a negative age must not amplify the score.
  assert.equal(policyDecay(-2, -5), -2);
});

test('the decay constant is the §5.2 thirty days', () => {
  assert.equal(POLICY_DECAY_DAYS, 30);
  // One full constant: -2 * exp(-30/30) = -2 * 0.3679 = -0.74.
  assert.equal(policyDecay(-2, POLICY_DECAY_DAYS), -0.74);
});

test('the staleness bound sits past one decay constant', () => {
  assert.equal(POLICY_STALE_DAYS, 45);
});