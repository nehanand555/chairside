-- Supabase-native scheduled transactional email worker (staging).
-- Invokes the already deployed Edge Function every minute with a Vault-held token.
-- The function validates this token via service-role-only email_validate_cron_token.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

select vault.create_secret(
  encode(gen_random_bytes(32), 'hex'),
  'spicyself_email_cron_token',
  'Internal staging scheduler token for SpicySelf email worker'
)
where not exists (select 1 from vault.secrets where name = 'spicyself_email_cron_token');

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
$fn$;
revoke all on function public.email_validate_cron_token(text) from public, anon, authenticated;
grant execute on function public.email_validate_cron_token(text) to service_role;

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
);
