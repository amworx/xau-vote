# TASK-04 — Supabase Backend

- **phase:** 4
- **plan:** `plans/2026-09-26_mvp-build-plan.md`
- **status:** complete (2026-09-29, mock-backed; live steps pending gates)
- **depends on:** TASK-03
- **gates:** **G2** (user confirmation before provisioning remote project / applying migrations)

## Scope

`supabase/` at project root.

### T4.1 — Apply migrations (G2)

- Provision free Supabase project (user action/confirmation).
- Apply `0001_initial.sql` from T0.1 (+ any follow-ups).
- Seed `sources` rows for mock/fixture sources.

### T4.2 — collect-ideas Edge Function

- Scheduled (pg_cron / scheduled functions) per enabled source.
- Runs adapters → normalization → filters → dedupe → upsert `trade_ideas`
  (unique on source_id+fingerprint).
- **Decision point:** if running Dart engines inside Edge Functions is impractical,
  port the thin orchestration to TypeScript while keeping `xau_core` as the source
  of truth — port must pass the SAME golden fixtures (shared JSON test vectors
  exported from Dart tests). Record decision in memory/decisions.md.

### T4.3 — build-consensus Edge Function

- Reads fresh valid `trade_ideas` → runs consensus → writes `consensus_signals`
  + `signal_sources` (with independence_weight, contribution_score).
- Emits NO CONSENSUS state record (or absence + status) when divided — never a
  fabricated signal.

### T4.4 — tick Edge Function

- Every minute (or free-tier-max frequency): fetch current price (provider,
  cached into `market_snapshots`), advance lifecycle for open signals, compute
  5M confirmation inputs, check expiration.

### T4.5 — Notifications (FCM)

- On lifecycle transitions, dispatch the 6 notification types (spec §16) with
  timestamp + price levels.
- Store notification state to avoid duplicate sends.

## Acceptance

- [ ] Scheduled run with fixture sources produces stored consensus signal rows
      matching the mock pipeline output (parity check vs TASK-03 test vectors).
- [ ] Lifecycle transitions advance correctly via tick; history timestamps stored.
- [ ] Notification delivered to a test device/token for: strong consensus,
      entry approaching, confirmation, invalidation, TP1.
- [ ] RLS verified: public can read active signals; cannot write.
- [ ] Memory: EVT + decisions recorded.

## Verification

- `supabase db diff`/migration list clean.
- SQL spot-checks via MCP.
- Function logs reviewed for one full cycle.
