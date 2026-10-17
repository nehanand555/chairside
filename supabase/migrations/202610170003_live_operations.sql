create table private.queue_refresh (resource_id uuid primary key references public.resources,last_at timestamptz not null default now());

create or replace function private.slot_free(p_resource uuid,p_start timestamptz,p_minutes integer,p_exclude uuid default null,p_include_queue boolean default true) returns boolean
language sql stable security definer set search_path='' as $$
  select p_start>=now()-interval '2 minutes' and p_start<now()+interval '90 days'
    and exists(select 1 from public.resources r join public.businesses b on b.id=r.business_id
      join public.hours h on h.business_id=b.id and h.weekday=extract(isodow from p_start at time zone b.timezone)
      where r.id=p_resource and r.active
        and (p_start at time zone b.timezone)::date=((p_start+make_interval(mins=>p_minutes)) at time zone b.timezone)::date
        and (p_start at time zone b.timezone)::time>=h.opens
        and ((p_start+make_interval(mins=>p_minutes)) at time zone b.timezone)::time<=h.closes)
    and not exists(select 1 from private.resource_breaks rb where resource_id=p_resource and tstzrange(starts_at,ends_at,'[)')&&tstzrange(p_start,p_start+make_interval(mins=>p_minutes),'[)'))
    and not exists(select 1 from public.visits v where resource_id=p_resource and (p_exclude is null or id<>p_exclude)
      and (status in ('booked','serving') or (p_include_queue and status='waiting'))
      -- A visit remains in service until the barber actually finishes it, including overruns.
      and tstzrange(starts_at,case when status='serving' then greatest(ends_at,now()+interval '5 minutes') else ends_at end,'[)')&&tstzrange(p_start,p_start+make_interval(mins=>p_minutes),'[)'))
$$;
create function public.refresh_queues() returns void language plpgsql security definer set search_path='' as $$
declare r record;
begin
  perform private.require_user();
  for r in select distinct v.resource_id,v.business_id from public.visits v where v.status='waiting'
    and (v.customer_id=auth.uid() or (private.owns(v.business_id) and auth.jwt()->>'aal'='aal2') or private.is_admin()) loop
    if pg_try_advisory_xact_lock(hashtextextended(r.business_id::text,0)) and not exists(select 1 from private.queue_refresh where resource_id=r.resource_id and last_at>now()-interval '25 seconds') then
      begin perform private.reflow_queue(r.resource_id); exception when raise_exception then null; end;
      insert into private.queue_refresh values(r.resource_id,now()) on conflict(resource_id) do update set last_at=now();
    end if;
  end loop;
end $$;
create function public.integration_tick() returns void language plpgsql security definer set search_path='' as $$
declare r record;
begin
  for r in select distinct resource_id,business_id from public.visits where status='waiting' limit 100 loop
    if pg_try_advisory_xact_lock(hashtextextended(r.business_id::text,0)) then
      begin perform private.reflow_queue(r.resource_id); exception when raise_exception then null; end;
    end if;
  end loop;
end $$;
create function public.my_visits(p_offset integer default 0,p_business uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform private.require_user();
  return (select coalesce(jsonb_agg(x.data),'[]') from (
    select to_jsonb(v)||jsonb_build_object('business_name',b.name,'resource_name',r.name,'online_payments',coalesce(a.charges_enabled,false),
      'queue_position',case when v.status='waiting' then (select count(*)+1 from public.visits q where q.resource_id=v.resource_id and q.status='waiting' and (q.created_at,q.id)<(v.created_at,v.id)) else null end) as data
    from public.visits v join public.businesses b on b.id=v.business_id join public.resources r on r.id=v.resource_id left join private.payment_accounts a on a.business_id=v.business_id
    where (p_business is null or v.business_id=p_business) and (v.customer_id=auth.uid() or (private.owns(v.business_id) and auth.jwt()->>'aal'='aal2') or private.is_admin())
    order by (v.status in ('booked','waiting','serving')) desc,v.created_at desc,v.id desc
    limit 200 offset greatest(0,least(p_offset,100000))
  ) x);
end $$;
create function public.search_businesses(p_query text) returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(x),'[]') from (select id,public_lat as lat,public_lng as lng from public.businesses where status='approved' and publish_consent
    and length(trim(p_query)) between 2 and 100 and position(lower(trim(p_query)) in lower(name||' '||suburb))>0 order by name limit 20) x
$$;
create function private.update_sms_preference() returns trigger language plpgsql security definer set search_path='' as $$
begin
  update private.visit_contacts set sms_consent=new.sms_updates where visit_id in(select id from public.visits where customer_id=new.id and status in ('booked','waiting','serving','cancelled'));
  return new;
end $$;
create trigger profile_sms_changed after update of sms_updates on public.profiles for each row execute function private.update_sms_preference();

create function public.admin_health() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_admin() then raise exception 'Admin access denied'; end if;
  return jsonb_build_object('failed_sms',(select count(*) from private.notification_outbox where state='failed'),
    'pending_sms',(select count(*) from private.notification_outbox where state='pending' and due_at<now()-interval '5 minutes'),
    'pending_refunds',(select count(*) from public.visits where payment_status='refund_pending'),
    'oldest_pending_refund',(select min(created_at) from public.visits where payment_status='refund_pending'));
end $$;
revoke execute on function public.refresh_queues(),public.integration_tick(),public.my_visits(integer,uuid),public.search_businesses(text),public.admin_health(),private.update_sms_preference() from public,anon,authenticated;
grant execute on function public.refresh_queues(),public.my_visits(integer,uuid),public.admin_health() to authenticated;
grant execute on function public.search_businesses(text) to anon,authenticated;
grant execute on all functions in schema public to service_role;
revoke all on all tables in schema private from anon,authenticated;
