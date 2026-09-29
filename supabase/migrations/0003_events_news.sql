-- XAU Radar — TASK-07: economic calendar + news intelligence schema.
-- File: supabase/migrations/0003_events_news.sql
-- Status: WRITTEN, NOT APPLIED. Paper migration only — do not run against
-- any database without explicit user confirmation (project Gate G2).
-- Extends docs/economic-calendar-news.md §6 (parent: docs/mvp-specification.md).
--
-- RULE 9 (AGENTS.md): events and news are context + guardrails, NEVER votes.
-- Nothing in this migration can create or flip a signal: there are no
-- triggers, no generated signals, no writes into consensus_signals.
--
-- Design notes:
-- * Times use TIMESTAMPTZ (UTC). Numeric results use NUMERIC (never FLOAT).
-- * `surprise` is a nullable TEXT flag computed post-release by fetch-events
--   / tick when actuals land: 'hot' (actual above forecast beyond threshold),
--   'cold' (below), 'inline' (within), NULL (no result yet). Direction-free:
--   it marks volatility risk only, never a trade direction.
-- * news_articles stores headlines + links + short summaries ONLY. Never
--   store full publisher article text (copyright rule, addendum §8).
-- * news_digests.themes is JSONB: [{ theme, pressure, evidence_urls[] }]
--   with pressure IN ('HAWKISH','DOVISH','NEUTRAL','UNCLEAR') enforced by
--   the writer (news-digest fn), not by a DB constraint, so future label
--   additions don't require a migration.
-- * RLS for the 3 new tables lives IN THIS FILE. 0002 stays frozen.
--   Model matches 0002: public (anon/authenticated) SELECT, writes via
--   service-role Edge Functions only.

-- ---------------------------------------------------------------------------
-- economic_events (addendum §6)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS economic_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider      TEXT NOT NULL CHECK (provider IN ('fmp', 'manual', 'forexfactory')),
  external_id   TEXT NOT NULL,
  title         TEXT NOT NULL,
  currency      TEXT NOT NULL DEFAULT 'USD',
  impact        TEXT NOT NULL CHECK (impact IN ('HIGH', 'MEDIUM', 'LOW')),
  starts_at     TIMESTAMPTZ NOT NULL,
  actual        NUMERIC,
  forecast      NUMERIC,
  previous      NUMERIC,
  surprise      TEXT CHECK (surprise IS NULL OR surprise IN ('hot', 'cold', 'inline')),
  url           TEXT,
  collected_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT economic_events_unique_provider_external UNIQUE (provider, external_id)
);

CREATE INDEX IF NOT EXISTS economic_events_currency_impact_starts_idx
  ON economic_events (currency, impact, starts_at);
CREATE INDEX IF NOT EXISTS economic_events_starts_idx
  ON economic_events (starts_at);

-- ---------------------------------------------------------------------------
-- news_articles (addendum §6 + §3.1; headlines + links only)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS news_articles (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_name   TEXT NOT NULL,
  url           TEXT NOT NULL UNIQUE,
  title         TEXT NOT NULL,
  summary       TEXT,
  published_at  TIMESTAMPTZ,
  collected_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  query_tag     TEXT,
  fingerprint   TEXT NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS news_articles_collected_idx
  ON news_articles (collected_at DESC);

-- ---------------------------------------------------------------------------
-- news_digests (addendum §6 + §3.2; fixed schema, display-only context)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS news_digests (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  window_start  TIMESTAMPTZ NOT NULL,
  window_end    TIMESTAMPTZ NOT NULL,
  themes        JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT news_digests_window_ck CHECK (window_start <= window_end)
);

CREATE INDEX IF NOT EXISTS news_digests_created_idx
  ON news_digests (created_at DESC);

-- ---------------------------------------------------------------------------
-- RLS (same model as 0002: public read, service-role writes only)
-- ---------------------------------------------------------------------------
ALTER TABLE economic_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE news_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE news_digests ENABLE ROW LEVEL SECURITY;

-- Public read: upcoming + recent events (guard state + Events screen).
CREATE POLICY "public read economic events"
  ON economic_events FOR SELECT
  TO anon, authenticated
  USING (true);

-- Public read: collected headlines (title + source + link only).
CREATE POLICY "public read news articles"
  ON news_articles FOR SELECT
  TO anon, authenticated
  USING (true);

-- Public read: latest digest (macro backdrop strip).
CREATE POLICY "public read news digests"
  ON news_digests FOR SELECT
  TO anon, authenticated
  USING (true);

-- No insert/update/delete policies for anon/authenticated on any of the
-- three tables: writes are service-role only (Edge Functions). Intentional.
