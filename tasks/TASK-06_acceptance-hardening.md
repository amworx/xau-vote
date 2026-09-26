# TASK-06 — Acceptance & Hardening

- **phase:** 6
- **plan:** `plans/2026-09-26_mvp-build-plan.md`
- **status:** pending
- **depends on:** TASK-04, TASK-05

## T6.1 — End-to-end acceptance walkthrough

Scripted evidence run of all 15 steps (spec §25):

| # | Step | Evidence |
|---|---|---|
| 1 | Current XAUUSD price fetched | log + app screenshot |
| 2 | Permitted ideas collected | trade_ideas rows |
| 3 | Timeframe identified | normalized fields |
| 4 | Only 15M-relevant kept | filter log counts |
| 5 | Stale rejected | filter log counts |
| 6 | Duplicates detected | independence weights in signal_sources |
| 7 | Direction agreement determined | consensus_signals.direction |
| 8 | Entry/SL/TP clustered | consensus levels vs source levels |
| 9 | Strength calculated | strength + band |
| 10 | 1H context checked | context badge / field |
| 11 | 5M confirmation monitored | lifecycle transitions |
| 12 | One clear setup produced | Signal screen |
| 13 | Lifecycle updated | status history timestamps |
| 14 | User notified | FCM payload + device receipt |
| 15 | Original sources preserved | Sources screen + sourceUrl links |

Deliverable: `docs/acceptance-run-YYYY-MM-DD.md` with evidence links/screenshots.

## T6.2 — Failure-mode matrix

Prove the system NEVER fabricates (spec §25 final rule):

- All ideas stale → NO CONSENSUS.
- Sources divided 2/2/1 → NO CONSENSUS with counts.
- Ideas missing SL/TP → INSUFFICIENT DATA, excluded from consensus.
- Market data unavailable → app shows last-known + staleness warning, no new signals.
- Single independent source (copies) → NO CONSENSUS or capped strength.
- Provider error/timeout → pipeline logs + skips cycle without corrupting state.

## T6.3 — Legal checklist

`docs/source-licensing-register.md`: one row per candidate source — URL, terms
URL, automation allowed?, commercial use allowed?, review date, verdict
(enabled/disabled/pending), notes. Register must exist even if all rows are
"pending" except mocks.

## Acceptance

- [ ] All 15 steps pass with captured evidence.
- [ ] Every failure mode produces the correct non-fabricated output.
- [ ] Licensing register exists and is current.
- [ ] Memory: OP- recorded (full MVP operation), lessons + patterns extracted.

## Verification

Manual scripted run + review of evidence doc; regression tests green.
