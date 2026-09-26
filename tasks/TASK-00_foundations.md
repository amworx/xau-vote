# TASK-00 — Foundations

- **phase:** 0
- **plan:** `plans/2026-09-26_mvp-build-plan.md`
- **status:** pending
- **gates:** none (no installs, no cloud)

## T0.1 — Supabase schema design

Design SQL migrations for the 5 tables from spec §21: `sources`, `trade_ideas`,
`consensus_signals`, `signal_sources`, `market_snapshots`.

Deliverable: `supabase/migrations/0001_initial.sql` (written, NOT applied).

Requirements:
- Appropriate Postgres types (numeric for prices, timestamptz for times, jsonb
  for take_profits array, text enums via check constraints).
- Indexes: `trade_ideas(symbol, timeframe, published_at)`, `trade_ideas(fingerprint)`,
  `consensus_signals(symbol, status)`, `market_snapshots(symbol, timestamp)`.
- RLS: policies sketched but disabled-by-default decisions documented
  (public read of active consensus signals; writes only via service role).
- Unique constraint preventing duplicate idea storage: `(source_id, fingerprint)`.

## T0.2 — xau_core domain models

Deliverable: `src/xau_core/lib/models/` pure Dart, no third-party packages.

Types:
- `TradeIdea` — every field from spec §4 structure.
- `ConsensusSignal` — direction, strength, entry zone, SL, TP1–3, status, timestamps, expiresAt.
- Enums: `Direction { long, short, neutral }`, `TradeTimeframe { m5, m15, h1 }`,
  `SignalStatus` (all states in spec §14), `Freshness { veryFresh, fresh, aging, expired }`,
  `ConsensusStrength { weak, developing, moderate, strong, veryStrong }` with the
  0–39/40–59/60–74/75–89/90–100 bands from spec §7.
- Value types: `PriceRange { low, high }`, `TakeProfit { index, price }`.
- Manual `toJson`/`fromJson` (no codegen in MVP).

## Acceptance

- [ ] Migration SQL parses (reviewed, not executed).
- [ ] Models round-trip JSON in `dart test`.
- [ ] Strength band mapping matches spec §7 exactly.
- [ ] Memory: EVT recorded.

## Verification

`dart test` inside `src/xau_core` (create with `dart create -t package` — part of
this task, no user gate needed since it is local tooling with zero third-party deps;
confirm with user first if any dependency beyond SDK is wanted).
