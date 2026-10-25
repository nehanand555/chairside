-- Supabase-native email scheduler; skip Supabase-specific extensions when running
-- ordinary PostgreSQL tests. Supabase staging has this scheduler deployed.
DO $outer$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_available_extensions WHERE name='pg_cron')
     OR NOT EXISTS (SELECT 1 FROM pg_available_extensions WHERE name='pg_net')
     OR to_regclass('vault.secrets') IS NULL
     OR to_regclass('vault.decrypted_secrets') IS NULL THEN
    RAISE NOTICE 'Supabase Cron/Vault unavailable; skipping platform-only email scheduler';
    RETURN;
  END IF;

  EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog';
  EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions';

  EXECUTE $secret$
select vault.create_secret(
  encode(gen_random_bytes(32), 'hex'),
  'spicyself_email_cron_token',
  'Internal staging scheduler token for SpicySelf email worker'
)
where not exists (select 1 from vault.secrets where name = 'spicyself_email_cron_token')
  $secret$;

  EXECUTE $func$
create or replace function public.email_validate_cron_token(p_token text)
returns boolean
language sql stable security definer set search_path = ''
as $fn$
  select coalesce(
    length(p_token) = 64 and
    encode(sha256(convert_to(p_token, 'UTF8')), 'hex') = (
      select encode(sha256(convert_to(decrypted_secret, 'UTF8')), 'hex')
      from vault.decrypted_secrets
      where name = 'spicyself_email_cron_token'
    ), false
  );
$fn$
  $func$;
  EXECUTE 'revoke all on function public.email_validate_cron_token(text) from public, anon, authenticated;';
  EXECUTE 'grant execute on function public.email_validate_cron_token(text) to service_role;';

  EXECUTE $scheduler$
select cron.schedule(
  'spicyself-staging-email-worker',
  '* * * * *',
  $job$
    select net.http_post(
      url := 'https://nylhyzveicmgqmckveyr.supabase.co/functions/v1/email-worker',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-token',
        (select decrypted_secret from vault.decrypted_secrets
         where name = 'spicyself_email_cron_token')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 25000
    );
  $job$
)
  $scheduler$;
END
$outer$;
