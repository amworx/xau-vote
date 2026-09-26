# XAU Radar — MVP Build Plan

- **date:** 2026-09-26
- **status:** approved for execution
- **spec:** `docs/mvp-specification.md` (authoritative)
- **goal:** Deliver the 15-step end-to-end acceptance flow (spec §25) with $0 infrastructure.

---

## 1. Guiding Constraints

1. Spec rules are inviolable (AGENTS.md "Core product rules"): no fabrication, 15M-only consensus, 1H never votes, source independence, licensing gate, provider abstraction.
2. Build order follows **testability first**: pure logic (consensus engine) before IO (adapters, DB, network).
3. Every external dependency (market data, idea sources) starts as a **Mock**; real adapters are added behind the same interface only after their licensing/automation review is recorded in `memory/decisions.md`.
4. Flutter app and backend logic share **one Dart codebase** for domain logic where possible: consensus/clustering/lifecycle code lives in a pure-Dart package usable by both the Flutter app and Supabase Edge Functions (Deno-compatible or compiled path decided per task).
5. No `flutter create`, package installs, or Supabase provisioning without explicit user confirmation at the start of the relevant phase.

---

## 2. Architecture (from spec §22, refined)

```
src/
├── xau_core/                  ← pure Dart package: domain models + engines (no Flutter, no I/O)
│   ├── models/                ← TradeIdea, ConsensusSignal, enums, value types
│   ├── consensus/             ← clustering, scoring, independence
│   ├── lifecycle/             ← signal state machine
│   └── context/               ← 1H context, 5M confirmation (deterministic rules)
├── xau_data/                  ← interfaces + implementations
│   ├── market_data/           ← MarketDataProvider, GoldApiProvider, MockProvider
│   └── idea_sources/          ← IdeaSource, adapters, MockSource
├── supabase/
│   ├── migrations/            ← schema (spec §21)
│   └── functions/             ← collect-ideas, build-consensus, tick (lifecycle/notifications)
└── app/                       ← Flutter app (5 screens, spec §24)
```

Backend pipeline (runs as scheduled Edge Functions):

```
collect-ideas (per source adapter)
   → normalize → filter (symbol/TF/freshness/actionable) → dedupe (fingerprint)
   → store trade_ideas
build-consensus
   → cluster entry/SL/TP → independence weighting → strength score
   → 1H context attach → store consensus_signals (+ signal_sources)
tick
   → market snapshot → lifecycle transitions (READY→CONFIRMED→ACTIVE→TP/INVALIDATED/EXPIRED)
   → dispatch notifications (FCM)
```

---

## 3. Phases

### Phase 0 — Foundations (no runtime deps)
- **T0.1** Supabase schema design: 5 tables (spec §21) + indexes + RLS sketch, as SQL migrations on paper.
- **T0.2** `xau_core` domain models: `TradeIdea`, `ConsensusSignal`, enums (Direction, Timeframe, SignalStatus, Freshness), value types (PriceRange, TakeProfit). Pure Dart, no packages.
- **Exit:** schema SQL reviewed; models compile + serialize (manual JSON, no codegen).

### Phase 1 — Consensus Engine (pure logic, fully unit-tested)
- **T1.1** Clustering: entry zones, SL, TP values with outlier rejection (spec §8, §9, §10).
- **T1.2** Deduplication & independence factor (spec §5): fingerprint comparison across direction/levels/wording/author/time.
- **T1.3** Consensus strength score 0–100 (spec §6, §7): direction agreement, zone agreement, SL/TP agreement, reasoning agreement, freshness, independence; 1H and 5M as modifiers, never votes.
- **T1.4** R:R calculation (spec §11).
- **Exit:** golden-file unit tests covering every example in the spec (§6 cluster example, §9 SL outlier, §11 R:R example). ≥90% coverage of engine code.

### Phase 2 — Lifecycle & Confirmation (pure logic)
- **T2.1** Signal state machine (spec §14): all transitions + timestamps, invalid transitions rejected.
- **T2.2** Expiration/freshness rules (spec §15).
- **T2.3** Deterministic 5M confirmation rules (spec §13): price-in-zone, invalidation level, structure flags provided as inputs (no TA library in MVP).
- **T2.4** 1H context classification (SUPPORTIVE / COUNTER-TREND / NEUTRAL).
- **Exit:** state machine tests including all three lifecycle paths in the spec.

### Phase 3 — Data Layer (interfaces + mocks)
- **T3.1** `MarketDataProvider` interface + `MockProvider` (scripted price series for tests).
- **T3.2** `IdeaSource` interface + `MockSource` fixtures (including the spec's A/B/C/D scenario and a copied-idea scenario).
- **T3.3** Gold API provider (spec §18) — **requires user confirmation**: terms permit commercial use; record licensing review in `memory/decisions.md` before enabling.
- **Exit:** end-to-end pipeline test using only mocks: ideas in → consensus out → lifecycle transitions driven by mock prices.

### Phase 4 — Supabase Backend
- **T4.1** Apply migrations (user confirmation required — creates remote project).
- **T4.2** `collect-ideas` Edge Function (per-source scheduling, stores normalized ideas).
- **T4.3** `build-consensus` Edge Function.
- **T4.4** `tick` Edge Function (lifecycle + notification dispatch).
- **T4.5** FCM integration for the 6 notification types (spec §16).
- **Exit:** scheduled pipeline produces stored consensus signals from mock/fixture sources; notifications delivered to a test device/token.

### Phase 5 — Flutter App (5 screens, spec §24)
- **T5.1** `flutter create` + project skeleton (user confirmation required) — Material 3, dark-first (trading app), portrait mobile-first.
- **T5.2** Screen 1 — Radar (live price, consensus card, NO CONSENSUS state; exact layout per spec §3).
- **T5.3** Screen 2 — Signal (full setup: entry zone, SL, TP1–3, R:R, lifecycle status, TP selection).
- **T5.4** Screen 3 — Sources (per-source breakdown with View Original, spec §17).
- **T5.5** Screen 4 — History (past signals + final status).
- **T5.6** Screen 5 — Settings (timeframes fixed display, target selection, notification toggles, spec §24).
- **T5.7** Supabase wiring: realtime/polling for active signal, FCM token registration.
- **Exit:** app runs against Supabase backend (or local mock mode flag) displaying all states.

### Phase 6 — Acceptance & Hardening
- **T6.1** Scripted walkthrough of all 15 acceptance steps (spec §25) with evidence (screenshots/logs).
- **T6.2** Failure-mode tests: stale ideas only, all sources divided, missing levels → correct NO CONSENSUS / INSUFFICIENT DATA.
- **T6.3** Legal checklist per source before any real adapter is enabled.

---

## 4. Build Order & Dependencies

```
Phase 0 ──→ Phase 1 ──→ Phase 2 ──→ Phase 3 ──→ Phase 4 ──→ Phase 5 ──→ Phase 6
                │           │           │                        ▲
                └───────────┴───────────┘                        │
                    (Phases 1–3 are pure Dart:                   │
                     can be built/tested locally                 │
                     before any cloud provisioning)      app can start in
                                                           MOCK MODE once
                                                           Phase 3 exists,
                                                           parallel with Phase 4
```

**User confirmation gates:**
- G1: before `flutter create` / any package install (Phase 5.1, Phase 0 if models want a package — prefer none)
- G2: before Supabase project provisioning + migrations (Phase 4.1)
- G3: before enabling Gold API provider (Phase 3.3)
- G4: before any real idea-source adapter (per-source licensing review)

---

## 5. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| No legally usable M15 idea sources found | Core value dead | Keep mock/fixture mode shippable; manual-curation adapter (human pastes ideas) as fallback source type |
| Gold API free tier limits/rate caps | Stale prices | Provider abstraction + caching in `market_snapshots`; tick interval tuned to free tier |
| Edge Function Dart support limits | Backend rewrite | Keep all engine logic in pure Dart `xau_core`; if Deno-Dart is impractical, run engine in `tick` via a thin TS port with shared golden tests — decision point at T4.2 |
| Copycat sources inflate consensus | False confidence | T1.2 independence weighting + per-source caps; tests include the spec's 4-copies scenario |
| Scope creep (social, brokers, more TFs) | MVP never ships | AGENTS.md core rules; spec §24 explicit exclusions |

---

## 6. Definition of Done (MVP)

1. All 15 acceptance steps (spec §25) demonstrably pass end-to-end.
2. Failure paths show NO CONSENSUS / INSUFFICIENT DATA (never fabricated output).
3. `xau_core` engines covered by unit tests incl. every numeric example in the spec.
4. Each enabled source adapter has a recorded licensing review.
5. 5 screens functional against live backend; notifications received on a real device.
6. Memory updated: events per phase, decisions logged, reusable patterns extracted.
