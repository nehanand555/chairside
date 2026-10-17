-- Run once in the chosen Supabase project's SQL editor AFTER activating the functions.
-- Add Vault secrets named chairside_functions_url and chairside_worker_secret in the
-- Dashboard first. The URL is https://PROJECT.supabase.co/functions/v1/notifications.
-- The worker secret must match the notifications function's WORKER_SECRET.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
do $$ begin
  if not exists(select 1 from vault.decrypted_secrets where name='chairside_functions_url')
    or not exists(select 1 from vault.decrypted_secrets where name='chairside_worker_secret') then
    raise exception 'Configure the two Chairside Vault secrets before scheduling';
  end if;
  if exists(select 1 from cron.job where jobname='chairside-every-minute') then perform cron.unschedule('chairside-every-minute'); end if;
end $$;
select cron.schedule('chairside-every-minute','* * * * *',$job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='chairside_functions_url' limit 1),
    headers := jsonb_build_object('Content-Type','application/json','x-worker-secret',(select decrypted_secret from vault.decrypted_secrets where name='chairside_worker_secret' limit 1)),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
$job$);
