-- General app feedback is private and separate from business incident reports.
create table private.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  message text not null check(length(message) between 10 and 2000),
  status text not null default 'open' check(status in ('open','resolved')),
  created_at timestamptz not null default now()
);
alter table private.feedback enable row level security;
revoke all on private.feedback from public,anon,authenticated;

create function public.submit_feedback(p_message text) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid := private.require_user(); m text := trim(coalesce(p_message,'')); result uuid;
begin
  if length(m) not between 10 and 2000 then raise exception 'Please write 10–2000 characters'; end if;
  if not public.integration_limit('feedback:'||u::text,5,3600) then
    raise exception 'Thanks for sharing. Please wait before sending more feedback';
  end if;
  insert into private.feedback(user_id,message) values(u,m) returning id into result;
  return result;
end $$;
revoke all on function public.submit_feedback(text) from public,anon;
grant execute on function public.submit_feedback(text) to authenticated;

create function public.admin_feedback() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_admin() or not exists(select 1 from auth.users where id=auth.uid() and lower(email)='spicynetwork75@gmail.com' and email_confirmed_at is not null and deleted_at is null) then raise exception 'Admin access denied; verify your authenticator'; end if;
  return coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at desc)
    from (select id,message,status,created_at from private.feedback where status='open' order by created_at desc limit 100) f),'[]');
end $$;
revoke all on function public.admin_feedback() from public,anon;
grant execute on function public.admin_feedback() to authenticated;

create function public.resolve_feedback(p_feedback uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.is_admin() or not exists(select 1 from auth.users where id=auth.uid() and lower(email)='spicynetwork75@gmail.com' and email_confirmed_at is not null and deleted_at is null) then raise exception 'Admin access denied; verify your authenticator'; end if;
  update private.feedback set status='resolved' where id=p_feedback;
end $$;
revoke all on function public.resolve_feedback(uuid) from public,anon;
grant execute on function public.resolve_feedback(uuid) to authenticated;
notify pgrst,'reload schema';
