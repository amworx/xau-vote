# Acceptance Run — 2026-09-29 (mock-backed)

All checks below ran locally with zero credentials. Live-DB/device steps are
marked PENDING with their runbook pointer. Evidence = test names + outputs.

## Result: 127/127 green · 4/4 analyzes clean · web release builds

| Suite | Result |
|---|---|
| `src/xau_core` dart test | 51 passed |
| `src/xau_lifecycle` dart test | 36 passed |
| `src/xau_data` dart test | 18 passed |
| `supabase/functions/_shared` node golden | 7 passed |
| `src/app` flutter test | 15 passed |
| `flutter build web` | ✓ Built build\web (45.8s) |

## Spec §25 walkthrough (steps 1–15)

| # | Step | Evidence | Status |
|---|---|---|---|
| 1 | Current XAUUSD price | `MockMarketDataProvider` scripted series; `currentPrice` fallback chain in `tick/` (provider → snapshot → explicit skip, never fabricated) | PASS (mock) |
| 2 | Collect permitted ideas | `collect-ideas` upserts with `(source_id,fingerprint)` dedupe; pipeline test counts stored | PASS (mock) |
| 3 | Identify timeframe | `TradeTimeframe` enum; intraday gate stage in pipeline | PASS |
| 4 | Keep 15M-relevant | Filter-chain order test (`pipeline_test.dart`) | PASS |
| 5 | Reject stale | Freshness boundary tests (14.9/15/30/60) + stale-only fixture → rejections | PASS |
| 6 | Detect duplicates | 4-copies → 1 independent vote (`independence_assessor_test`, `DIVIDED` guard) | PASS |
| 7 | LONG/SHORT agreement | A/B/C/D → LONG, D excluded (`consensus_engine_test`) | PASS |
| 8 | Cluster Entry/SL/TP | Golden `cluster-long.json` (entry 4275–4280 exact, SL ≈4263, TP1 ≈4296) | PASS |
| 9 | Consensus strength | A/B/C → ≈82 STRONG; threshold + share guards | PASS |
| 10 | 1H context | `ContextClassifier` attaches SUPPORTIVE; regression test proves score unchanged | PASS |
| 11 | 5M confirmation | E2E: developing→ready→confirmed→active→tp1Hit (`pipeline_test.dart`) | PASS |
| 12 | One clear setup | `ConsensusOutcome` (signal + breakdown + counts) | PASS |
| 13 | Lifecycle updates | Timestamped history; illegal transitions throw | PASS |
| 14 | Notify user | FCM payload assembly in `tick/` (topics, timestamp, levels); RADAR/Signal/Events widget states | PASS (mock) / PENDING device receipt |
| 15 | Original sources preserved | `signal_sources` join rows; Sources screen + View Original | PASS (mock) |

## Addendum steps 16–23 (economic calendar + news)

| # | Step | Evidence | Status |
|---|---|---|---|
| 16 | Fetch USD HIGH/MED events | `fetch-events` ManualSeed + FMP-gated provider (code) | PASS (mock) |
| 17 | Blackout suppress + resume | Golden guard edges (`isBlackout` T−30/+15); blackout widget test; `suppressedBy` audit | PASS |
| 18 | Lift + resume scanning | `tick` expiry/lift path; blackout-lift notice queued | PASS (mock) |
| 19 | 60m + 15m warnings | Queued in `tick`; Events countdown UI | PASS (mock) / PENDING device |
| 20 | Actuals + surprises | Surprise flags (NFP ±50K, CPI ±0.2pp); Results tab | PASS (mock) |
| 21 | News collect + headlines | `news-collect` dedupe; News tab with link-outs; no full text stored | PASS (mock) |
| 22 | Hourly digest + backdrop | Fixed-schema digest + UNCLEAR fallback; MacroBackdropStrip | PASS (mock) |
| 23 | Events never vote | Divided + blackout paths emit NO_CONSENSUS (widget + engine tests) | PASS |

## PENDING (need user action / credentials)

- G2: Supabase project + `db push` + deploy + schedules → then re-run steps 1–2, 12–15 live per `docs/backend-runbook.md §5`.
- Device: FCM receipt on a real device (needs Firebase project, runbook §6).
- G3/G4/G5: provider licensing reviews before any real adapter is enabled.
- License choice (README flags TBD).

## Failure-mode matrix (all green)

Stale-only → NO CONSENSUS · divided 2/2/1 → NO CONSENSUS with counts ·
missing levels → INSUFFICIENT DATA · single source → NO CONSENSUS ·
provider absent → tick skips with explicit reason · event storm → NO CONSENSUS.
