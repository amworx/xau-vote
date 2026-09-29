-- XAU Radar — initial schema (spec §21)
-- File: supabase/migrations/0001_initial.sql
-- Status: WRITTEN, NOT APPLIED. Review only; do not run against prod without
-- explicit user confirmation (project gate G2).
--
-- Design notes:
-- * Prices use NUMERIC (gold needs exact decimal arithmetic; never FLOAT).
-- * Times use TIMESTAMPTZ (UTC).
-- * take_profits uses JSONB array of numbers, e.g. '[4295, 4315, 4340]'.
--   TP1–TP3 columns on consensus_signals are flattened NUMERIC for easy query.
-- * Text enums are enforced via CHECK constraints (no custom ENUM types yet so
--   future value additions don't require ALTER TYPE migrations).
-- * Unique (source_id, fingerprint) prevents duplicate idea storage.
--
-- RLS DECISIONS (documented, NOT enforced yet):
-- * Desired end state: public (anon) read of ACTIVE/READY/CONFIRMED consensus
--   signals + their signal_sources + market_snapshots latest; everything else
--   readable only by authenticated service consumers; ALL writes via service
--   role only (Edge Functions use SERVICE_ROLE key, never anon key).
-- * RLS is intentionally NOT enabled in this migration. When the backend
--   phase (T4.1) provisions Supabase, enable RLS per table and apply the
--   sketched policies in the "SKETCHED RLS POLICIES (do not apply yet)" block
--   at the bottom of this file after review.
-- * Licensing gate reminder: no RLS policy grants write to anon/authenticated;
--   source adapters run server-side only.

-- Required extension for gen_random_uuid().
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
-- sources
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sources (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                   TEXT NOT NULL,
  url                    TEXT NOT NULL,
  license_url            TEXT,
  automation_allowed     BOOLEAN NOT NULL DEFAULT FALSE,
  commercial_use_allowed BOOLEAN NOT NULL DEFAULT FALSE,
  enabled                BOOLEAN NOT NULL DEFAULT FALSE,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- trade_ideas (spec §4 + fingerprint for §5 dedupe)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS trade_ideas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id             UUID NOT NULL REFERENCES sources (id) ON DELETE CASCADE,
  symbol                TEXT NOT NULL DEFAULT 'XAUUSD' CHECK (symbol = 'XAUUSD'),
  timeframe             TEXT NOT NULL CHECK (timeframe IN ('M5', 'M15', 'H1')),
  direction             TEXT NOT NULL CHECK (direction IN ('long', 'short', 'neutral')),
  entry_low             NUMERIC,
  entry_high            NUMERIC,
  stop_loss             NUMERIC,
  take_profits          JSONB NOT NULL DEFAULT '[]'::jsonb,
  trigger_condition     TEXT,
  invalidation_condition TEXT,
  reasoning             TEXT,
  author                TEXT,
  published_at          TIMESTAMPTZ,
  collected_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  fingerprint           TEXT NOT NULL,
  CONSTRAINT trade_ideas_entry_range_ck CHECK (
    entry_low IS NULL OR entry_high IS NULL OR entry_low <= entry_high
  ),
  CONSTRAINT trade_ideas_unique_source_fingerprint UNIQUE (source_id, fingerprint)
);

CREATE INDEX IF NOT EXISTS trade_ideas_symbol_tf_published_idx
  ON trade_ideas (symbol, timeframe, published_at DESC);
CREATE INDEX IF NOT EXISTS trade_ideas_fingerprint_idx
  ON trade_ideas (fingerprint);
CREATE INDEX IF NOT EXISTS trade_ideas_source_published_idx
  ON trade_ideas (source_id, published_at DESC);

-- ---------------------------------------------------------------------------
-- consensus_signals (spec §14 lifecycle states)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS consensus_signals (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  symbol      TEXT NOT NULL DEFAULT 'XAUUSD' CHECK (symbol = 'XAUUSD'),
  timeframe   TEXT NOT NULL DEFAULT 'M15' CHECK (timeframe = 'M15'),
  direction   TEXT NOT NULL CHECK (direction IN ('long', 'short', 'neutral')),
  strength    INTEGER NOT NULL CHECK (strength >= 0 AND strength <= 100),
  entry_low   NUMERIC NOT NULL,
  entry_high  NUMERIC NOT NULL,
  stop_loss   NUMERIC NOT NULL,
  tp1         NUMERIC,
  tp2         NUMERIC,
  tp3         NUMERIC,
  status      TEXT NOT NULL DEFAULT 'DEVELOPING' CHECK (status IN (
                'NO_SETUP', 'DEVELOPING', 'READY', 'CONFIRMED', 'ACTIVE',
                'TP1_HIT', 'TP2_HIT', 'TP3_HIT', 'INVALIDATED', 'EXPIRED'
              )),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ,
  CONSTRAINT consensus_signals_entry_range_ck CHECK (entry_low <= entry_high)
);

CREATE INDEX IF NOT EXISTS consensus_signals_symbol_status_idx
  ON consensus_signals (symbol, status);
CREATE INDEX IF NOT EXISTS consensus_signals_created_idx
  ON consensus_signals (created_at DESC);

-- ---------------------------------------------------------------------------
-- signal_sources (join: which ideas contributed, with independence weighting)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS signal_sources (
  signal_id           UUID NOT NULL REFERENCES consensus_signals (id) ON DELETE CASCADE,
  trade_idea_id       UUID NOT NULL REFERENCES trade_ideas (id) ON DELETE CASCADE,
  independence_weight NUMERIC NOT NULL DEFAULT 1 CHECK (
    independence_weight > 0 AND independence_weight <= 1
  ),
  contribution_score  NUMERIC CHECK (
    contribution_score IS NULL OR (contribution_score >= 0 AND contribution_score <= 100)
  ),
  PRIMARY KEY (signal_id, trade_idea_id)
);

CREATE INDEX IF NOT EXISTS signal_sources_signal_idx
  ON signal_sources (signal_id);
CREATE INDEX IF NOT EXISTS signal_sources_idea_idx
  ON signal_sources (trade_idea_id);

-- ---------------------------------------------------------------------------
-- market_snapshots
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS market_snapshots (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  symbol    TEXT NOT NULL DEFAULT 'XAUUSD' CHECK (symbol = 'XAUUSD'),
  price     NUMERIC NOT NULL,
  bid       NUMERIC,
  ask       NUMERIC,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS market_snapshots_symbol_ts_idx
  ON market_snapshots (symbol, timestamp DESC);

-- ---------------------------------------------------------------------------
-- SKETCHED RLS POLICIES (do not apply yet — review at T4.1)
--
-- -- Enable RLS when backend is provisioned:
-- -- ALTER TABLE sources ENABLE ROW LEVEL SECURITY;
-- -- ALTER TABLE trade_ideas ENABLE ROW LEVEL SECURITY;
-- -- ALTER TABLE consensus_signals ENABLE ROW LEVEL SECURITY;
-- -- ALTER TABLE signal_sources ENABLE ROW LEVEL SECURITY;
-- -- ALTER TABLE market_snapshots ENABLE ROW LEVEL SECURITY;
--
-- -- Public read of actionable consensus signals only:
-- -- CREATE POLICY "public_read_active_signals" ON consensus_signals
-- --   FOR SELECT TO anon USING (status IN ('READY','CONFIRMED','ACTIVE'));
-- -- CREATE POLICY "public_read_signal_sources" ON signal_sources
-- --   FOR SELECT TO anon USING (EXISTS (
-- --     SELECT 1 FROM consensus_signals s WHERE s.id = signal_id
-- --       AND s.status IN ('READY','CONFIRMED','ACTIVE')));
-- -- CREATE POLICY "public_read_latest_price" ON market_snapshots
-- --   FOR SELECT TO anon USING (true);
--
-- -- No anon/authenticated writes: writes service_role only.
-- -- (With RLS enabled and no write policies for anon/authenticated, writes
-- -- are denied by default; Edge Functions bypass RLS with SERVICE_ROLE key.)
-- ---------------------------------------------------------------------------
