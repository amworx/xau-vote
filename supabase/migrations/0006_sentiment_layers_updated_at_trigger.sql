-- sentiment_layers.updated_at had a default but no trigger, so every upsert left
-- the original timestamp in place. That made it impossible to tell a fresh
-- scheduled write from a frozen value -- the exact question you need answered
-- when a cron job silently stops running.
create or replace function public.touch_sentiment_layers_updated_at()
returns trigger
language plpgsql
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

drop trigger if exists sentiment_layers_touch_updated_at on sentiment_layers;
create trigger sentiment_layers_touch_updated_at
  before update on sentiment_layers
  for each row
  execute function public.touch_sentiment_layers_updated_at();