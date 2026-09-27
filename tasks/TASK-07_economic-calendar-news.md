# TASK-07 — Economic Calendar & News Intelligence

- **phase:** 7 (after Phase 4 backend; app work parallel with Phase 5)
- **plan:** `plans/2026-09-26_mvp-build-plan.md` + `docs/economic-calendar-news.md` (authoritative for this task)
- **status:** pending
- **depends on:** TASK-04 (backend patterns), TASK-03 (provider-interface pattern)
- **gates:** **G5** (user confirmation + recorded licensing review before enabling FMP or any news provider; manual-seed mode needs no gate)

## Scope

Implement `docs/economic-calendar-news.md` in rollout order (§10). Rules from
addendum §1 are inviolable: events/news are context + guardrails, never votes.

### T7.1 — Schema + guard state

- Migration `0002_events_news.sql`: `economic_events`, `news_articles`,
  `news_digests` (+ indexes) per addendum §6.
- Guard-state helper: `is_blackout(now, currency='USD')` + `next_high_event(now)`
  queries; unit-testable in pure Dart (`xau_core` guard module) with fixture events.

### T7.2 — fetch-events function + manual seed

- `EventProvider` interface + `FmpProvider` (GATED) + `ManualSeed` (JSON fixture
  of known recurring events: NFP first Friday, CPI monthly, FOMC 8×/yr — clearly
  labeled approximate, replaced by provider data when enabled).
- Scheduled hourly; computes surprise flags when actuals land.
- Acceptance: NFP fixture → blackout window computed correctly; unit tests for
  window edges (T−30:00 open vs T−29:59 closed).

### T7.3 — Guard integration

- `build-consensus`: suppress new signals in blackout (log suppression with
  event id); attach MEDIUM-event context to developing signals.
- `tick`: countdown state, blackout-lift resume, surprise detection.
- Regression test (addendum §9 step 23): event storm + divided ideas → NO CONSENSUS.

### T7.4 — Event notifications

- 60m + 15m HIGH warnings, blackout-lift notice, surprise alerts (FCM).
- Test-device receipts recorded as evidence.

### T7.5 — News collection + Events screen headlines tab

- `NewsProvider` interface + `ManualNews` seed; GNews adapter written but
  enabled for dev/test only until commercial licensing resolved.
- Query plan sized to the chosen tier (addendum §8 quota math).
- Events screen: Upcoming / Results / Headlines tabs (digest tab arrives in T7.6).

### T7.6 — AI digest + macro backdrop

- Hourly digest with FIXED output schema `{ theme, pressure, evidence_urls[] }`.
- UNCLEAR fallback required; golden tests: hawkish set → HAWKISH, mixed set →
  UNCLEAR (never forced).
- Radar "Macro backdrop" strip wired to latest digest.

### T7.7 — Events screen + radar banner + settings

- Screen 6 per addendum §5.2; blackout banner per §5.1 (replaces signal card,
  countdown ticks); Settings event group per §5.3.
- Follows the chosen design system; MOCK_MODE fixtures include a HIGH event
  scenario (banner state must be previewable offline).

## Acceptance

- [ ] All 8 criteria (addendum §9 steps 16–23) pass with evidence.
- [ ] No enabled provider without a recorded licensing review.
- [ ] Full article text never stored/displayed (spot-check DB + UI).
- [ ] Step-23 regression green.
- [ ] Memory: EVT + decisions (per-provider reviews).

## Verification

`dart test` (guard logic) · function logs · device notification receipts ·
evidence doc appended to `docs/acceptance-run-*`.
