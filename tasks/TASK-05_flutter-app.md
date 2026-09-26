# TASK-05 — Flutter App (5 screens)

- **phase:** 5
- **plan:** `plans/2026-09-26_mvp-build-plan.md`
- **status:** pending
- **depends on:** TASK-03 (mock mode) · TASK-04 (live mode)
- **gates:** **G1** (user confirmation before `flutter create` / pub installs)

## Scope

`src/app/` — Flutter, Material 3, dark-first (trading UI), portrait mobile-first.
State: simple (Provider or Riverpod — decide at kickoff, record decision).
App reads `xau_core`/`xau_data` as path packages. **MOCK_MODE flag** runs the app
fully offline from fixtures — build this FIRST, then wire live Supabase.

UI work must follow the global UI Design Playbook (`~/.config/opencode/ui-design.md`).

### T5.1 — Skeleton (G1)

`flutter create`, theme (dark, gold accent), routing (bottom nav or simple
navigator for 5 screens), MOCK_MODE wiring.

### T5.2 — Screen 1: Radar (spec §3, exact layout)

- LIVE indicator, current price (large), 15M consensus card: direction arrow,
  strength label, entry zone, SL, TP1–3, R:R, "N / M sources agree", VIEW ANALYSIS → Screen 2.
- NO CONSENSUS state: LONG/SHORT/NEUTRAL counts + "Waiting for stronger agreement."
- NEVER show fabricated signal; stale data shows staleness visibly.

### T5.3 — Screen 2: Signal

Full setup detail: levels, R:R per TP, lifecycle status with timeline,
1H context badge (SUPPORTIVE / COUNTER-TREND), 5M confirmation state,
TP selection control (spec §10: TP1 / TP1+TP2 / TP1+TP2+TP3).
Consensus strength shown as agreement label — NEVER as win probability (spec §7).

### T5.4 — Screen 3: Sources (spec §17)

Per-source cards: ✓/✗ agreement, direction, entry, SL, TPs, freshness age,
"View Original" → opens sourceUrl externally.

### T5.5 — Screen 4: History

Past signals: direction, levels, final status (TP1/2/3 HIT, INVALIDATED, EXPIRED),
timestamps. Newest first.

### T5.6 — Screen 5: Settings (spec §24)

Timeframes display (15M/5M/1H — fixed in MVP), target selection, notification
toggles (consensus, entry, confirmation, invalidation, targets). Persist via
Supabase user preferences (or local storage pre-auth).

### T5.7 — Live wiring

Supabase: subscribe/poll active consensus signal + price; FCM token registration
and foreground notification display. No auth in MVP if RLS allows public read —
decide at kickoff.

## Acceptance

- [ ] All 5 screens render correctly in MOCK_MODE for: strong consensus,
      no consensus (divided), developing, invalidated, expired, TP-hit states.
- [ ] Layout of Radar matches spec §3 structure closely (screenshot compare).
- [ ] Live mode displays backend signal + receives FCM notification on device.
- [ ] No speculative UI beyond the 5 screens (spec §24 exclusions honored).
- [ ] `flutter analyze` clean; widget tests for Radar + Signal states.
- [ ] Memory: EVT + patterns.

## Verification

`flutter analyze` · `flutter test` · manual run on emulator/device in both modes.
