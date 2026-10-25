-- Fail closed even if an unintended account remains in private.admins.
-- Email is read from Auth-owned verified state, never JWT user_metadata.
create or replace function private.admin_identity_allowed() returns boolean
language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from private.admins a
    join auth.users u on u.id=a.user_id
    where a.user_id=auth.uid()
      and lower(u.email)='spicynetwork75@gmail.com'
      and u.email_confirmed_at is not null and u.deleted_at is null
      and not exists(select 1 from private.blocked_users b where b.user_id=u.id)
  )
$$;
revoke all on function private.admin_identity_allowed() from public,anon,authenticated;

create or replace function private.is_admin() returns boolean
language sql stable security definer set search_path='' as $$
  select private.admin_identity_allowed()
    and coalesce(auth.jwt()->>'aal','')='aal2'
$$;

create or replace function public.account_context() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid := private.require_user();
begin
  return jsonb_build_object(
    'is_admin',private.admin_identity_allowed(),
    'business_id',(select id from public.businesses where owner_id=u and status<>'closed'),
    'business_status',(select status from public.businesses where owner_id=u and status<>'closed'),
    'business_review_note',(select review_note from public.businesses where owner_id=u and status<>'closed'),
    'aal2',auth.jwt()->>'aal'='aal2'
  );
end $$;

-- Ask PostgREST to discover the updated RPC definitions after deployment.
notify pgrst, 'reload schema';
