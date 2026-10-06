-- 0012_sentiment_layers_drop_gold_fundamentals.sql
--
-- D-20261006-011. gold_fundamentals is REMOVED, not pending.
--
-- The World Gold Council data this layer would need is licensed for personal,
-- non-commercial use only. Scraping or redistributing it requires written
-- authorisation we do not have, so the layer is unobtainable rather than
-- unbuilt. Recording it as a null "not built yet" row drew the wrong
-- distinction and, worse, pinned macro-side coverage at 55/75 = 73% forever -
-- a ceiling that reads as permanent incompleteness rather than as an honest
-- statement of what can legally be measured.
--
-- Enforcement lives in the DATABASE, not only in the ingest function. The
-- function is not the only thing that can write `sentiment_layers`, and a
-- decision that holds only while one deploy stays current is not a decision.
--
-- The app-side counterpart (weights, denominators, UI, fixtures) lives in the
-- same commit: expectedWeights drops the layer, macroSideWeight becomes 55, and
-- overallCoverage divides by the 80-point claim instead of a literal 100.

-- Remove the stored row.
delete from public.sentiment_layers where layer = 'gold_fundamentals';

-- Refuse any future insert or update of the layer, loudly rather than silently.
-- A trigger over a CHECK constraint is deliberate: a CHECK could only constrain
-- the weight column, not forbid the layer outright.
create or replace function public.sentiment_layers_forbid_gold_fundamentals()
returns trigger
language plpgsql
as $$
begin
  if new.layer = 'gold_fundamentals' then
    raise exception
      'gold_fundamentals is removed (D-20261006-011): World Gold Council data is '
      'licensed for personal, non-commercial use only and we hold no authorisation. '
      'Restoring the layer requires a licensed source, not a code change.';
  end if;
  return new;
end;
$$;

drop trigger if exists sentiment_layers_forbid_gold on public.sentiment_layers;
create trigger sentiment_layers_forbid_gold
  before insert or update on public.sentiment_layers
  for each row execute function public.sentiment_layers_forbid_gold_fundamentals();

comment on function public.sentiment_layers_forbid_gold_fundamentals() is
  'Refuses gold_fundamentals rows. D-20261006-011: the source cannot be licensed.';