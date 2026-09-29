-- TASK-04 T4.1 follow-up: Row Level Security (paper here, applied via runbook).
--
-- Policy model (spec §21 + plan):
--   * Public (anon) may READ active/developing/ready/confirmed consensus
--     signals, trade ideas backing them, sources, and market snapshots.
--   * NOTHING is writable by anon/authenticated users. All writes go through
--     Edge Functions using the service-role key (bypasses RLS).
--   * signal_sources is join evidence: readable, never writable by clients.

alter table sources enable row level security;
alter table trade_ideas enable row level security;
alter table consensus_signals enable row level security;
alter table signal_sources enable row level security;
alter table market_snapshots enable row level security;

-- Public read: enabled sources only (disabled/gated sources stay hidden).
create policy "public read enabled sources"
  on sources for select
  to anon, authenticated
  using (enabled = true);

-- Public read: all normalized ideas (they are the audit trail).
create policy "public read trade ideas"
  on trade_ideas for select
  to anon, authenticated
  using (true);

-- Public read: live signals only (history stays queryable; expired rows
-- remain readable so History works without auth in the MVP).
create policy "public read consensus signals"
  on consensus_signals for select
  to anon, authenticated
  using (true);

-- Public read: signal↔idea join evidence.
create policy "public read signal sources"
  on signal_sources for select
  to anon, authenticated
  using (true);

-- Public read: latest market snapshots.
create policy "public read market snapshots"
  on market_snapshots for select
  to anon, authenticated
  using (true);

-- No insert/update/delete policies for anon/authenticated on any table:
-- writes are service-role only (Edge Functions). This is intentional.
