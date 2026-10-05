-- Sentiment layers from instruction/XAUUSD_IMPLEMENTATION_READY_METHODOLOGY.md
-- §5.1. One row per layer, holding the measured score plus the evidence it came
-- from, so a verdict can always be traced back to a source and a date.
--
-- Weights are the methodology's, not ours (§5.1):
--   policy 35, positioning 25, gold_fundamentals 20, market_implied 20.
create table if not exists sentiment_layers (
  id uuid primary key default gen_random_uuid(),

  -- policy | positioning | gold_fundamentals | market_implied
  layer text not null unique,
  horizon text not null,
  weight numeric not null,

  -- Raw §5 score where that layer defines one (policy -2..+2, positioning
  -- -2..+2). NULL when the layer could not be measured - never a fabricated 0.
  score smallint,

  -- -1/0/+1 directional alignment for the confluence engine's
  -- MacroState.alignment / SentimentState.alignment.
  alignment smallint,

  measured_at timestamptz not null,
  source text not null,
  source_url text,

  -- True when the reading is older than the layer's natural refresh cycle.
  -- §27 Failure 4: COT must never be treated as current.
  stale boolean not null default false,

  -- The measured inputs behind the score (percentile, managed_net, yields...).
  detail jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint sentiment_layers_score_range check (score is null or score between -2 and 2),
  constraint sentiment_layers_alignment_range check (alignment is null or alignment between -1 and 1)
);

comment on table sentiment_layers is
  'Slow sentiment layers per methodology §5.1. Read by the app; written only by the sentiment-layers Edge Function.';

alter table sentiment_layers enable row level security;

drop policy if exists "public read sentiment layers" on sentiment_layers;
create policy "public read sentiment layers" on sentiment_layers
  for select to anon, authenticated using (true);

create index if not exists sentiment_layers_measured_at_idx
  on sentiment_layers (measured_at desc);