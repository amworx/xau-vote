-- 0015_ledger_settlement_columns.sql
--
-- The settlement writes several diagnostic fields the ledger never declared:
-- exit_price, spread_cost_r and bars_used. Postgres rejects the whole UPDATE when
-- any target column is unknown, so settle() failed with a 500 instead of writing
-- anything. Found by settling a real episode rather than by reading the writer.
--
-- `outcome` is intentionally left as text: it carries both the pre-registered
-- result vocabulary (STOP_FIRST / TARGET_FIRST / TIMEOUT) and data-quality
-- suffixes such as HORIZON_BAR_GAP:8/12. Constraining it to an enum would force
-- a second column for the gap marker, which is worse than a documented text
-- vocabulary.

alter table public.xv_outcome_ledger
  add column if not exists exit_price    double precision,
  add column if not exists spread_cost_r double precision,
  add column if not exists bars_used     int;

comment on column public.xv_outcome_ledger.outcome is
  'STOP_FIRST / TARGET_FIRST / TIMEOUT, optionally suffixed with a data-quality '
  'marker such as +HORIZON_BAR_GAP:8/12. Text rather than enum so a data gap is '
  'recorded on the same row instead of forcing a second column.';

comment on column public.xv_outcome_ledger.net_outcome is
  'measured_spread when a usable cost measurement existed at settlement, '
  'cost_model_unavailable otherwise. Never a fabricated cost.';