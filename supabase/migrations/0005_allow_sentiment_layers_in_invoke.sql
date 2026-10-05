-- cron.schedule('xv-sentiment-layers', ...) succeeded, but xv_invoke_function
-- validates its argument against a hardcoded allowlist. Without this entry the
-- nightly job would have raised on every run and the layer would have silently
-- frozen on its last value while the job still reported success in cron.job.
create or replace function public.xv_invoke_function(fn_name text)
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
    'sentiment-layers'
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
    body    := '{}'::jsonb
  );
end;
$function$;

comment on function public.xv_invoke_function(text) is
  'Invokes an allowlisted Edge Function with the vault service-role key. The allowlist is the only gate; a scheduled job naming a function missing from it raises.';