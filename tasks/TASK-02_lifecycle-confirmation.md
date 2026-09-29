# TASK-02 — Lifecycle & Confirmation (pure logic)

- **phase:** 2
- **plan:** `plans/2026-09-26_mvp-build-plan.md`
- **status:** complete (2026-09-29, mock-backed; live steps pending gates)
- **depends on:** TASK-01
- **gates:** none

## Scope

`src/xau_core/lib/lifecycle/` and `src/xau_core/lib/context/`.

### T2.1 — Signal state machine

States (spec §14): `noSetup, developing, ready, confirmed, active,
tp1Hit, tp2Hit, tp3Hit, invalidated, expired`.

- Legal transitions only:
  - developing → ready | invalidated | expired
  - ready → confirmed | invalidated | expired
  - confirmed → active | invalidated | expired
  - active → tp1Hit | invalidated
  - tp1Hit → tp2Hit | invalidated
  - tp2Hit → tp3Hit | invalidated
- Every transition stamped; history list kept on the signal.
- Illegal transition → exception in tests / ignored + logged in prod mode.

### T2.2 — Expiration & freshness

`FreshnessPolicy` (spec §15):
- <15 min VERY_FRESH · 15–30 FRESH · 30–60 AGING · 60+ EXPIRED/context-only.
- `expiresAt` computed at idea/signal creation; policy is injectable (per-source
  override later).
- Signals in ready/confirmed past `expiresAt` → EXPIRED via state machine.

### T2.3 — 5M confirmation (deterministic)

`ConfirmationEvaluator`: inputs = current price, recent 5M structure flags
(provided externally: breakoutRetest, rejection, momentum), signal levels.
Outputs: `developing | ready | confirmed | invalidated`.
- ready: price enters consensus entry zone.
- confirmed: ready + structure agrees (rule table defined in code; MVP = any one
  confirming flag while price holds zone).
- invalidated: price closes beyond invalidation level (SL side).

### T2.4 — 1H context

`ContextClassifier`: input = 1H trend direction (externally supplied enum for MVP)
+ signal direction → `SUPPORTIVE | COUNTER_TREND | NEUTRAL` (spec §12).
Context is attached to the signal as metadata — never alters the consensus score.

## Acceptance

- [ ] All three lifecycle paths from spec §14 walk correctly with timestamps.
- [ ] Invalid transitions rejected.
- [ ] Freshness bands exact at boundaries (14:59 vs 15:00 min etc.).
- [ ] Confirmation: ready→confirmed requires structure flag; SL breach → invalidated
      from any active-ish state.
- [ ] Context never changes score (regression test: same ideas + different 1H → same score).
- [ ] Memory: EVT recorded.

## Verification

`dart test` in `src/xau_core`.
