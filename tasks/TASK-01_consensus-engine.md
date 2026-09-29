# TASK-01 — Consensus Engine (pure logic)

- **phase:** 1
- **plan:** `plans/2026-09-26_mvp-build-plan.md`
- **status:** complete (2026-09-29, mock-backed; live steps pending gates)
- **depends on:** TASK-00 (models)
- **gates:** none — pure Dart, unit tests only

## Scope

All logic lives in `src/xau_core/lib/consensus/`. No I/O, no clocks injected
implicitly — pass `DateTime now` in for testability.

### T1.1 — Clustering

`PriceClusterer`: given a list of numbers (or PriceRanges), produce consensus
cluster(s) with outlier rejection.
- Entry: overlapping/nearby zones merge → consensus zone (spec §8: 4275, 4277–4281,
  4279, 4280–4283 → 4277–4281).
- SL: same; the 4300 outlier in spec §9 must be excluded → 4262–4265.
- TP: cluster per TP index (TP1s together, TP2s, TP3s).
- Define "near" as a configurable tolerance (default: relative to recent ATR-free
  fixed point window — decision: start with max(1.5 points, cluster span × 0.5),
  tune in tests).

### T1.2 — Deduplication & independence

`IndependenceAssessor`:
- Fingerprint each idea: normalized (direction, entry mid rounded, SL rounded,
  TP set rounded, author, rounded published minute-bucket).
- Two ideas with near-identical levels AND (same author OR overlapping wording
  similarity OR publish times within a few minutes in correlated sources) → same
  independent group.
- Output per idea: `independenceWeight` in (0, 1]; identical copies → only the
  earliest counts as 1, rest → small epsilon.
- Must handle spec §5 scenario: 4 copies → 1 independent vote.

### T1.3 — Consensus strength score

`ConsensusEngine.build(ideas, now)` → `ConsensusSignal | NoConsensus`.
Components (spec §6): direction agreement, entry-zone agreement, SL agreement,
TP agreement, reasoning agreement, freshness, source independence.
- Direction decided by independence-weighted majority of the dominant cluster.
- Score 0–100; map to bands per spec §7.
- Threshold: below MODERATE (60) or fewer than 2 independent sources → NO CONSENSUS.
- NEVER emit a score framed as win probability (spec §7).
- 1H/5M inputs are NOT part of this score (context/confirmation are separate).

### T1.4 — R:R

`RiskReward`: given entry zone mid (or worst-case edge), SL, TP list →
risk, reward per TP, R:R per TP. Must reproduce spec §11 example:
entry 4278, SL 4263 → risk 15; TP1 4295 → 17 pts (1:1.13); TP2 4315 → 1:2.47;
TP3 4340 → 1:4.13.

## Acceptance

- [ ] Spec §6 example: A/B/C cluster LONG → strength ≥ STRONG, entry 4275–4280,
      SL ~4263, TP1 ~4296, TP2 ~4317; D (SHORT) excluded from cluster.
- [ ] Spec §5 scenario: 4 identical ideas → 1 independent vote.
- [ ] Spec §9 outlier excluded.
- [ ] Spec §11 numbers exact.
- [ ] Divided sources (2L/2S/1N, spec §3) → NO CONSENSUS with counts exposed.
- [ ] Single independent source → NO CONSENSUS.
- [ ] ≥90% line coverage on `consensus/`.
- [ ] Memory: EVT + patterns extracted.

## Verification

`dart test` in `src/xau_core`.
