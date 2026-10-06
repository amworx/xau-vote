-- 0019_consensus_levels_nullable.sql
--
-- A non-signal has no levels, and the schema must be able to say so.
--
-- `build-consensus` writes one audit row per run. When there is no consensus
-- (no sources, a single source, a divided room, a blackout, a weak score) that
-- row carries direction 'neutral', strength 0, status EXPIRED - and, correctly,
-- no entry/stop/target, because inventing levels for a non-signal would be
-- fabrication.
--
-- But entry_low, entry_high and stop_loss were NOT NULL with no default, so
-- every one of those audit writes failed with "null value in column entry_low
-- violates not-null constraint" - one error every 5 minutes, confirmed in
-- postgres_logs. The function ignored the insert error and still returned
-- HTTP 200, so ten hours of runs reported success while writing nothing. The
-- last audit row is 2026-10-06 11:22 UTC; everything after it is missing.
--
-- The fix is NULL, not a sentinel. Writing 0 (or any number) into the levels
-- of a NO_CONSENSUS row would put a fabricated number where the app, the
-- ledger, or a future reader could mistake it for a real quote. NULL is the
-- honest value and every reader already treats it that way: the app maps a
-- level-less row to no signal, and the consensus builder only reads open rows,
-- which always carry real clustered levels on the success path.
--
-- The function is fixed alongside this to check its audit writes and fail
-- loudly instead of returning 200 on a silent write failure, so this class of
-- outage can never hide again.

alter table public.consensus_signals
  alter column entry_low drop not null,
  alter column entry_high drop not null,
  alter column stop_loss drop not null;

comment on column public.consensus_signals.entry_low is
  'NULL when the row is a non-signal audit record (NO_CONSENSUS/BLACKOUT), '
  'which must never carry invented levels. Open setup rows always have real '
  'clustered values.';
comment on column public.consensus_signals.entry_high is
  'NULL when the row is a non-signal audit record (NO_CONSENSUS/BLACKOUT), '
  'which must never carry invented levels. Open setup rows always have real '
  'clustered values.';
comment on column public.consensus_signals.stop_loss is
  'NULL when the row is a non-signal audit record (NO_CONSENSUS/BLACKOUT), '
  'which must never carry invented levels. Open setup rows always have real '
  'clustered values.';