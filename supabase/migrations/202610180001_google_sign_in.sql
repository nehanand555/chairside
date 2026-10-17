-- Add Google identities without modifying any already-deployed migration.
-- Trust Auth-owned identities, never caller-controlled profile/user_metadata fields.
create or replace function private.require_user() returns uuid language plpgsql volatile security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(
    select 1 from auth.users u where u.id=auth.uid() and u.deleted_at is null and (
      (u.phone_confirmed_at is not null and nullif(u.phone,'') is not null)
      or (u.email_confirmed_at is not null and exists(
        select 1 from auth.identities i where i.user_id=u.id and i.provider='google'
      ))
    )
  ) or exists(select 1 from private.blocked_users where user_id=auth.uid()) then
    raise exception 'Please sign in with Google or a verified phone number';
  end if;
  return auth.uid();
end $$;

create or replace function public.create_visit(p_business uuid,p_service uuid,p_resource uuid,p_kind text,p_start timestamptz default null,p_walk_in jsonb default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); b public.businesses; s public.services; vid uuid; customer uuid:=u; customer_name text; phone text; sms boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_business::text,0));
  select * into b from public.businesses where id=p_business;
  if b.status<>'approved' or not b.publish_consent then raise exception 'This business is not accepting bookings'; end if;
  select * into s from public.services where id=p_service and business_id=b.id and active;
  if s.id is null or not exists(select 1 from public.resources where id=p_resource and business_id=b.id and active) then raise exception 'Choose an available service and chair'; end if;
  if p_walk_in is not null then
    perform private.require_operator(b.id);
    if p_kind<>'queue' then raise exception 'Walk-ins must join the queue'; end if;
    customer:=null; customer_name:=trim(p_walk_in->>'name'); phone:=nullif(p_walk_in->>'phone',''); sms:=coalesce((p_walk_in->>'sms_consent')::boolean,false);
  else
    select display_name,sms_updates into customer_name,sms from public.profiles where id=u;
    -- Supabase Auth normalises stored phone numbers without the leading plus.
    select case when au.phone_confirmed_at is not null and nullif(au.phone,'') is not null
      then '+'||ltrim(au.phone,'+') end into phone from auth.users au where au.id=u;
    if coalesce(customer_name,'')='' then raise exception 'Add your name in Account first'; end if;
  end if;
  if p_kind='appointment' then
    if p_start is null or p_start<now()+interval '5 minutes' or not private.slot_free(p_resource,p_start,s.minutes) then raise exception 'That appointment is no longer available'; end if;
  elsif p_kind='queue' then
    if b.kind='home' or not b.queue_open then raise exception 'The live queue is paused'; end if;
    if (select count(*) from public.visits where resource_id=p_resource and status='waiting')>=30 then raise exception 'Queue is full'; end if;
    p_start:=date_trunc('minute',now())+interval '1 minute';
  else raise exception 'Choose appointment or queue'; end if;
  insert into public.visits(business_id,resource_id,service_id,customer_id,customer_name,service_name,minutes,price_cents,kind,status,starts_at,ends_at)
  values(b.id,p_resource,s.id,customer,customer_name,s.name,s.minutes,s.price_cents,p_kind,case when p_kind='queue' then 'waiting' else 'booked' end,p_start,p_start+make_interval(mins=>s.minutes)) returning id into vid;
  if phone is not null then insert into private.visit_contacts values(vid,phone,coalesce(sms,false)); end if;
  if p_kind='queue' then perform private.reflow_queue(p_resource); end if;
  insert into private.notification_outbox(visit_id,kind) values(vid,'confirmation');
  if p_kind='appointment' and p_start>now()+interval '90 minutes' then insert into private.notification_outbox(visit_id,kind,due_at) values(vid,'reminder',p_start-interval '1 hour'); end if;
  return vid;
exception when unique_violation then raise exception 'You already have an active visit, or that slot was just taken. Refresh and try again';
  when exclusion_violation then raise exception 'That slot was just taken. Choose another time';
end $$;

create or replace function public.admin_overview() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_admin() then raise exception 'Admin access denied; verify your authenticator'; end if;
  return jsonb_build_object('businesses',coalesce((select jsonb_agg(to_jsonb(b)||jsonb_build_object('location',to_jsonb(l),'owner_phone',(select nullif(phone,'') from auth.users where id=b.owner_id),'owner_email',(select email from auth.users where id=b.owner_id)) order by b.created_at desc) from public.businesses b join private.business_locations l on l.business_id=b.id),'[]'),
    'reports',coalesce((select jsonb_agg(r order by r.created_at desc) from public.reports r where status='open'),'[]'));
end $$;

-- CREATE OR REPLACE preserves existing privileges; keep private helpers inaccessible.
revoke execute on function private.require_user() from public,anon,authenticated;
