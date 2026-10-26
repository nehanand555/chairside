-- Allow Supabase-verified Apple identities, alongside Google or verified phone.
-- Identity rows are Auth-managed; caller-controlled metadata is not trusted.
create or replace function private.require_user()
returns uuid
language plpgsql volatile security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(
    select 1 from auth.users u
    where u.id = auth.uid()
      and u.deleted_at is null
      and (
        (u.phone_confirmed_at is not null and nullif(u.phone, '') is not null)
        or (
          u.email_confirmed_at is not null
          and exists (
            select 1 from auth.identities i
            where i.user_id = u.id
              and i.provider in ('google', 'apple')
          )
        )
      )
  ) or exists(
    select 1 from private.blocked_users where user_id = auth.uid()
  ) then
    raise exception 'Please sign in with Google, Apple or a verified phone number';
  end if;
  return auth.uid();
end $$;
