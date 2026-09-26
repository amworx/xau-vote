# TASK-03 — Data Layer (interfaces + mocks)

- **phase:** 3
- **plan:** `plans/2026-09-26_mvp-build-plan.md`
- **status:** pending
- **depends on:** TASK-02
- **gates:** T3.3 requires **Gate G3** (user confirmation + recorded licensing review)

## Scope

`src/xau_data/` pure Dart (no Flutter).

### T3.1 — MarketDataProvider interface + Mock

```dart
abstract class MarketDataProvider {
  Future<PriceQuote> currentPrice(String symbol);        // XAUUSD
  Stream<PriceQuote> watchPrice(String symbol, Duration interval);
}
```
- `PriceQuote { symbol, price, bid, ask, timestamp }`.
- `MockProvider`: scripted tick series (drives lifecycle tests deterministically).

### T3.2 — IdeaSource interface + Mock

```dart
abstract class IdeaSource {
  SourceInfo get info;   // name, url, licenseUrl, automationAllowed, commercialUseAllowed
  Future<List<TradeIdea>> fetchRecent({required DateTime since});
}
```
- `MockSource` fixtures:
  1. spec §6 A/B/C/D scenario,
  2. four-copies-of-one-idea scenario (spec §5),
  3. divided market (2L/2S/1N, spec §3),
  4. stale-only ideas (all >60 min),
  5. missing-levels idea (must normalize to INSUFFICIENT DATA, not fabricate).

### T3.3 — GoldApiProvider (GATED)

- **Precondition:** licensing review recorded in `memory/decisions.md`
  (spec §18 cites Gold API terms permitting commercial use; verify current terms
  URL and record date + key excerpts).
- Free tier; API key via env/config, never committed.
- Rate-limit aware (respect free-tier caps; cache into market_snapshots later).

### T3.4 — Pipeline orchestrator (offline)

`RadarPipeline`: sources → normalize → filter chain (spec §4 order: XAUUSD →
intraday → 15M-relevant → fresh → actionable → not-duplicate) → consensus →
context → lifecycle tick using MarketDataProvider.

Runs fully on mocks; this is the integration harness for Phases 1–3.

## Acceptance

- [ ] End-to-end mock run: A/B/C/D fixture → STRONG LONG consensus → price script
      drives ready → confirmed → active → tp1Hit.
- [ ] Divided fixture → NO CONSENSUS.
- [ ] Stale fixture → NO CONSENSUS (all filtered).
- [ ] Missing-levels fixture → idea rejected as INSUFFICIENT DATA with reason logged.
- [ ] Swapping MockProvider for another MarketDataProvider impl requires zero
      pipeline changes (interface conformance test).
- [ ] T3.3: terms verification doc exists BEFORE provider is enabled.
- [ ] Memory: EVT + decision (if T3.3 done).

## Verification

`dart test` in `src/xau_data`; integration test in `test/pipeline_test.dart`.
