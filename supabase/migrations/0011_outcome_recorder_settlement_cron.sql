-- 0011_outcome_recorder_settlement_cron.sql
--
-- Settlement needs a scheduled runner. Until this exists, `action=settle` only
-- ran when a human happened to curl it, so pending decisions would sit
-- unresolved indefinitely and the record would look like it was working while
-- containing nothing but PENDING rows.
--
-- Two changes:
--
--  1. xv_invoke_function gains a payload argument. It previously hardcoded an
--     empty body, which is fine for functions that act on no input but useless
--     for the recorder, which dispatches on action. The original one-argument
--     signature is KEPT as a wrapper so the existing cron jobs keep working
--     unchanged; several jobs already depend on it.
--
--  2. outcome-recorder joins the allowlist. The allowlist is the only gate on
--     which functions a scheduled job can reach, so an omitted name fails loudly
--     rather than silently doing nothing.
--
-- Every 15 minutes, aligned to the M15 bar close rather than to the wall clock.
-- Scanning every 15 minutes when the engine only produces a new decision at a
-- bar close would be pointless load.

-- ---------------------------------------------------------------------------
-- Payload-aware invoker
-- ---------------------------------------------------------------------------
create or replace function public.xv_invoke_function(fn_name text, payload jsonb)
  returns bigint
  language plpgsql
  security definer
  set search_path to 'public', 'extensions'
as $function$
declare
  svc_key text;
  base_url text := 'https://mfrzwmqgwgcyaxehdbqh.supabase.co/functions/v1/';
begin
  if fn_name not in (
    'tick', 'build-consensus', 'collect-ideas',
    'fetch-events', 'news-collect', 'news-digest', 'keepalive',
    'build-bars', 'oanda-quote',
    'sentiment-layers', 'outcome-recorder'
  ) then
    raise exception 'xv_invoke_function: % is not an allowed function name', fn_name;
  end if;

  select decrypted_secret into svc_key
    from vault.decrypted_secrets
   where name = 'xv_service_role_key';

  if svc_key is null then
    raise exception 'xv_invoke_function: vault secret xv_service_role_key is missing';
  end if;

  return net.http_post(
    url     := base_url || fn_name,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'apikey',       svc_key,
                 'Authorization', 'Bearer ' || svc_key
               ),
    body    := coalesce(payload, '{}'::jsonb)
  );
end;
$function$;

comment on function public.xv_invoke_function(text, jsonb) is
  'Invokes an allowlisted Edge Function with the vault service-role key. The '
  'allowlist is the only gate; a scheduled job naming a function missing from it '
  'raises rather than failing quietly.';

-- Backward-compatible wrapper: every pre-existing cron job calls the one-arg form.
create or replace function public.xv_invoke_function(fn_name text)
  returns bigint
  language sql
as $function$
  select public.xv_invoke_function(fn_name, '{}'::jsonb);
$function$;

-- ---------------------------------------------------------------------------
-- Settlement schedule
--
-- Run idempotently: unschedule any previous runner of the same name first, so
-- re-applying this migration cannot leave two settlement jobs double-settling.
-- Settlement is idempotent per row anyway, but two jobs is two table scans for
-- no benefit.
-- ---------------------------------------------------------------------------
do $$
declare
  existing bigint;
begin
  select jobid into existing
    from cron.job
   where jobname = 'xv-settle-outcomes';

  if existing is not null then
    perform cron.unschedule(existing);
  end if;

  -- Off the hour: bar closes land at :00/:15/:30/:45, and settlement needs the
  -- closing bar to already be stored. Waiting 4 minutes avoids racing the bar
  -- builder for the same bar.
  perform cron.schedule(
    'xv-settle-outcomes',
    '4-59/15 * * * *',
    $cron$ select public.xv_invoke_function('outcome-recorder', '{"action":"settle"}'::jsonb); $cron$
  );
end;
$$;