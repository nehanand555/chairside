-- Additive workspace APIs. No existing visits, payments or approval states change.
create table private.client_notes (
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id uuid not null references auth.users(id) on delete cascade,
  note text not null check(length(note)<=2000),
  updated_at timestamptz not null default now(),
  primary key(business_id,customer_id)
);
alter table private.client_notes enable row level security;
revoke all on private.client_notes from public,anon,authenticated;
create index visits_business_schedule on public.visits(business_id,starts_at,id) where kind='appointment';
create index visits_business_client on public.visits(business_id,customer_id,starts_at desc) where customer_id is not null;

create function public.business_overview(p_business uuid,p_day date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform private.require_operator(p_business);
  select jsonb_build_object(
    'appointments',count(*) filter(where kind='appointment' and status in ('booked','serving','completed')),
    'booked_value_cents',coalesce(sum(price_cents) filter(where kind='appointment' and status in ('booked','serving','completed')),0),
    'completed',count(*) filter(where status='completed')) into result
  from public.visits where business_id=p_business
    and starts_at>=p_day::timestamp at time zone 'Pacific/Auckland'
    and starts_at<(p_day+1)::timestamp at time zone 'Pacific/Auckland';
  return result||jsonb_build_object('waiting',(select count(*) from public.visits where business_id=p_business and status='waiting'),
    'active_resources',(select count(*) from public.resources where business_id=p_business and active));
end $$;

create function public.business_schedule(p_business uuid,p_day date,p_days integer default 1,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;
begin
  perform private.require_operator(p_business);
  if p_day is null or p_days not in (1,7) or p_offset not between 0 and 100000 then raise exception 'Invalid schedule range'; end if;
  select coalesce(jsonb_agg(x.data order by x.starts_at,x.id),'[]') into items from (
    select v.id,v.starts_at,to_jsonb(v)||jsonb_build_object('resource_name',r.name,'business_name',b.name,'online_payments',false) data
    from public.visits v join public.resources r on r.id=v.resource_id join public.businesses b on b.id=v.business_id
    where v.business_id=p_business and v.kind='appointment'
      and v.starts_at>=p_day::timestamp at time zone 'Pacific/Auckland'
      and v.starts_at<(p_day+p_days)::timestamp at time zone 'Pacific/Auckland'
    order by v.starts_at,v.id limit 101 offset p_offset
  ) x;
  return jsonb_build_object('items',case when jsonb_array_length(items)>100 then items-100 else items end,
    'has_more',jsonb_array_length(items)>100);
end $$;

create function public.business_clients(p_business uuid,p_search text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;
begin
  perform private.require_operator(p_business);
  if length(p_search)>100 or p_offset not between 0 and 100000 then raise exception 'Invalid client search'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.last_visit desc,x.customer_id),'[]') into items from (
    select v.customer_id,(array_agg(v.customer_name order by v.created_at desc,v.id desc))[1] as name,
      count(*) as visit_count,max(v.starts_at) as last_visit,coalesce(n.note,'') as note
    from public.visits v left join private.client_notes n on n.business_id=v.business_id and n.customer_id=v.customer_id
    where v.business_id=p_business and v.customer_id is not null
    group by v.customer_id,n.note
    having position(lower(trim(p_search)) in lower((array_agg(v.customer_name order by v.created_at desc,v.id desc))[1]))>0
    order by max(v.starts_at) desc,v.customer_id limit 51 offset p_offset
  ) x;
  return jsonb_build_object('items',case when jsonb_array_length(items)>50 then items-50 else items end,'has_more',jsonb_array_length(items)>50);
end $$;

create function public.save_client_note(p_business uuid,p_customer uuid,p_note text) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform private.require_operator(p_business);
  if not exists(select 1 from public.visits where business_id=p_business and customer_id=p_customer) then raise exception 'Client not found'; end if;
  if p_note is null or length(p_note)>2000 then raise exception 'Keep client notes under 2000 characters'; end if;
  insert into private.client_notes values(p_business,p_customer,trim(p_note),now())
    on conflict(business_id,customer_id) do update set note=excluded.note,updated_at=now();
  insert into private.audit(actor_id,action,subject_id,details) values(auth.uid(),'client_note_updated',p_business,jsonb_build_object('customer_id',p_customer));
end $$;

create function public.operator_book_appointment(p_business uuid,p_service uuid,p_resource uuid,p_start timestamptz,p_name text,p_customer uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.services; result uuid;
begin
  perform private.require_operator(p_business);
  perform pg_advisory_xact_lock(hashtextextended(p_business::text,0));
  if not exists(select 1 from public.businesses where id=p_business and status='approved' and publish_consent) then raise exception 'Business must be approved'; end if;
  if length(trim(coalesce(p_name,''))) not between 2 and 100 then raise exception 'Enter a client name'; end if;
  if p_customer is not null and not exists(select 1 from public.visits where business_id=p_business and customer_id=p_customer) then raise exception 'Client not found'; end if;
  select * into s from public.services where id=p_service and business_id=p_business and active;
  if s.id is null or not exists(select 1 from public.resources where id=p_resource and business_id=p_business and active) then raise exception 'Choose an active service and professional'; end if;
  if p_start is null or p_start<now()+interval '5 minutes' or not private.slot_free(p_resource,p_start,s.minutes) then raise exception 'That slot was just taken. Choose another time'; end if;
  insert into public.visits(business_id,resource_id,service_id,customer_id,customer_name,service_name,minutes,price_cents,kind,status,starts_at,ends_at)
    values(p_business,p_resource,s.id,p_customer,trim(p_name),s.name,s.minutes,s.price_cents,'appointment','booked',p_start,p_start+make_interval(mins=>s.minutes)) returning id into result;
  if p_customer is not null then
    insert into private.visit_contacts(visit_id,phone,sms_consent)
      select result,'+'||ltrim(u.phone,'+'),coalesce(p.sms_updates,false) from auth.users u join public.profiles p on p.id=u.id
      where u.id=p_customer and u.phone_confirmed_at is not null and nullif(u.phone,'') is not null;
  end if;
  insert into private.notification_outbox(visit_id,kind) values(result,'confirmation');
  if p_start>now()+interval '90 minutes' then insert into private.notification_outbox(visit_id,kind,due_at) values(result,'reminder',p_start-interval '1 hour'); end if;
  insert into private.audit(actor_id,action,subject_id,details) values(auth.uid(),'manual_appointment_booked',result,'{}');
  return result;
exception when exclusion_violation then raise exception 'That slot was just taken. Choose another time';
end $$;

create function public.reschedule_visit(p_visit uuid,p_start timestamptz,p_resource uuid default null) returns void
language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); v public.visits; b uuid; r uuid;
begin
  select business_id into b from public.visits where id=p_visit;
  if b is null then raise exception 'Appointment not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(b::text,0));
  select * into v from public.visits where id=p_visit for update;
  if v.customer_id is distinct from u then perform private.require_operator(b); end if;
  if v.status<>'booked' or v.kind<>'appointment' or v.payment_status in ('refund_pending','refunded') then raise exception 'This appointment cannot be rescheduled'; end if;
  if v.starts_at<=now() then raise exception 'This appointment has already started'; end if;
  if not exists(select 1 from public.businesses where id=b and status='approved' and publish_consent) then raise exception 'Business is unavailable'; end if;
  r:=coalesce(p_resource,v.resource_id);
  if not exists(select 1 from public.resources where id=r and business_id=b and active) then raise exception 'Choose an active professional'; end if;
  if p_start is null or p_start<now()+interval '5 minutes' or not private.slot_free(r,p_start,v.minutes,v.id) then raise exception 'That slot was just taken. Choose another time'; end if;
  perform 1 from private.notification_outbox where visit_id=v.id and kind='reminder' for update;
  if exists(select 1 from private.notification_outbox where visit_id=v.id and kind='reminder' and state='sending') then raise exception 'A notification is being sent. Please retry shortly'; end if;
  update private.notification_outbox set due_at=p_start-interval '1 hour',state=case when p_start>now()+interval '90 minutes' then 'pending' else 'skipped' end
    where visit_id=v.id and kind='reminder' and state in ('pending','skipped');
  if p_start>now()+interval '90 minutes' then insert into private.notification_outbox(visit_id,kind,due_at) values(v.id,'reminder',p_start-interval '1 hour') on conflict do nothing; end if;
  update public.visits set starts_at=p_start,ends_at=p_start+make_interval(mins=>v.minutes),resource_id=r where id=p_visit;
  insert into private.audit(actor_id,action,subject_id,details) values(u,'appointment_rescheduled',v.id,jsonb_build_object('previous_start',v.starts_at,'new_start',p_start));
end $$;

revoke all on function public.business_overview(uuid,date),public.business_schedule(uuid,date,integer,integer),public.business_clients(uuid,text,integer),public.save_client_note(uuid,uuid,text),public.operator_book_appointment(uuid,uuid,uuid,timestamptz,text,uuid),public.reschedule_visit(uuid,timestamptz,uuid) from public,anon;
grant execute on function public.business_overview(uuid,date),public.business_schedule(uuid,date,integer,integer),public.business_clients(uuid,text,integer),public.save_client_note(uuid,uuid,text),public.operator_book_appointment(uuid,uuid,uuid,timestamptz,text,uuid),public.reschedule_visit(uuid,timestamptz,uuid) to authenticated;
notify pgrst,'reload schema';

create function public.business_client_history(p_business uuid,p_customer uuid,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform private.require_operator(p_business);
  if p_offset not between 0 and 100000 then raise exception 'Invalid history page'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select id,service_name,starts_at,status,price_cents from public.visits where business_id=p_business and customer_id=p_customer
    order by starts_at desc,id desc limit 25 offset p_offset
  ) x),'[]');
end $$;
revoke all on function public.business_client_history(uuid,uuid,integer) from public,anon;
grant execute on function public.business_client_history(uuid,uuid,integer) to authenticated;

create function public.admin_business_page(p_status text default 'pending',p_search text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb; reports jsonb;
begin
  if not private.is_admin() then raise exception 'Admin access denied; verify your authenticator'; end if;
  if p_status not in ('pending','approved','rejected','suspended','all') or length(p_search)>100 or p_offset not between 0 and 100000 then raise exception 'Invalid business search'; end if;
  select coalesce(jsonb_agg(x.data order by x.created_at desc,x.id),'[]') into items from (
    select b.id,b.created_at,to_jsonb(b)||jsonb_build_object('location',to_jsonb(l),'registration_number',a.registration_number,'contact_name',a.contact_name,'contact_email',a.contact_email,'contact_phone',a.contact_phone) data
    from public.businesses b left join private.business_locations l on l.business_id=b.id left join private.business_applications a on a.business_id=b.id
    where (p_status='all' or b.status=p_status) and position(lower(trim(p_search)) in lower(b.name||' '||b.suburb))>0
    order by b.created_at desc,b.id limit 51 offset p_offset
  ) x;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into reports from (select r.*,b.name as business_name from public.reports r join public.businesses b on b.id=r.business_id where r.status='open' order by r.created_at desc,r.id limit 100) r;
  return jsonb_build_object('businesses',case when jsonb_array_length(items)>50 then items-50 else items end,'has_more',jsonb_array_length(items)>50,'reports',reports);
end $$;

create function public.admin_workspace_insights() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_admin() then raise exception 'Admin access denied; verify your authenticator'; end if;
  return jsonb_build_object(
    'business_counts',(select coalesce(jsonb_object_agg(status,total),'{}') from (select status,count(*) total from public.businesses group by status) x),
    'memberships',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select b.name,s.business_id,s.stripe_customer_id,s.stripe_subscription_id,s.status,s.current_period_end,s.cancel_at_period_end,s.updated_at from public.business_subscriptions s join public.businesses b on b.id=s.business_id order by s.updated_at desc limit 100) x),
    'audit',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select id,actor_id,action,subject_id,created_at from private.audit order by created_at desc,id desc limit 50) x));
end $$;
revoke all on function public.admin_business_page(text,text,integer),public.admin_workspace_insights() from public,anon;
grant execute on function public.admin_business_page(text,text,integer),public.admin_workspace_insights() to authenticated;

-- Remove notes when existing account-deletion logic anonymises the last visit.
create function private.remove_orphan_client_note() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if old.customer_id is not null and not exists(select 1 from public.visits where business_id=old.business_id and customer_id=old.customer_id) then
    delete from private.client_notes where business_id=old.business_id and customer_id=old.customer_id;
  end if;
  return null;
end $$;
revoke all on function private.remove_orphan_client_note() from public,anon,authenticated;
create trigger remove_orphan_client_note after update of customer_id or delete on public.visits for each row execute function private.remove_orphan_client_note();

-- Extend the existing service configuration API; preserve old clients and prices.
alter table public.services add column category text not null default 'General' check(length(category) between 1 and 60);
create or replace function public.configure_business(p_business uuid,p_action text,p_data jsonb default '{}') returns void language plpgsql security definer set search_path='' as $$
declare v uuid; item jsonb;
begin
  perform private.require_operator(p_business);
  perform pg_advisory_xact_lock(hashtextextended(p_business::text,0));
  if p_action='queue' then
    if exists(select 1 from public.businesses where id=p_business and kind='home') and (p_data->>'open')::boolean then raise exception 'Home studios accept appointments only'; end if;
    update public.businesses set queue_open=(p_data->>'open')::boolean where id=p_business;
  elsif p_action='service' then
    if p_data ? 'category' and length(trim(coalesce(p_data->>'category',''))) not between 1 and 60 then raise exception 'Category must contain 1–60 characters'; end if;
    if nullif(p_data->>'id','') is null then
      insert into public.services(business_id,name,minutes,price_cents,category) values(p_business,p_data->>'name',(p_data->>'minutes')::integer,(p_data->>'price_cents')::integer,coalesce(nullif(trim(p_data->>'category'),''),'General'));
    else
      update public.services set category=coalesce(nullif(trim(p_data->>'category'),''),category),name=p_data->>'name',minutes=(p_data->>'minutes')::integer,price_cents=(p_data->>'price_cents')::integer,active=coalesce((p_data->>'active')::boolean,true) where id=(p_data->>'id')::uuid and business_id=p_business;
      if not found then raise exception 'Service not found'; end if;
    end if;
  elsif p_action='resource' then
    if nullif(p_data->>'id','') is null then
      if (select count(*) from public.resources where business_id=p_business)>=20 then raise exception 'Maximum 20 chairs'; end if;
      insert into public.resources(business_id,name) values(p_business,p_data->>'name');
    else
      if exists(select 1 from public.visits where resource_id=(p_data->>'id')::uuid and status in ('waiting','booked','serving')) then raise exception 'Finish or cancel this chair’s visits before disabling it'; end if;
      update public.resources set name=p_data->>'name',active=(p_data->>'active')::boolean where id=(p_data->>'id')::uuid and business_id=p_business;
    end if;
  elsif p_action='hours' then
    if exists(select 1 from public.visits where business_id=p_business and status in ('booked','waiting','serving')) then raise exception 'Hours cannot change while there are active visits. Finish or cancel them first'; end if;
    delete from public.hours where business_id=p_business;
    for item in select * from jsonb_array_elements(p_data->'hours') loop
      insert into public.hours values(p_business,(item->>'weekday')::integer,(item->>'opens')::time,(item->>'closes')::time);
    end loop;
  elsif p_action='break' then
    if not exists(select 1 from public.resources where id=(p_data->>'resource_id')::uuid and business_id=p_business and active) then raise exception 'Chair not found'; end if;
    if (p_data->>'minutes')::integer not between 5 and 480 or not private.slot_free((p_data->>'resource_id')::uuid,(p_data->>'starts_at')::timestamptz,(p_data->>'minutes')::integer) then raise exception 'Break conflicts with a visit, another break, or opening hours'; end if;
    insert into private.resource_breaks(business_id,resource_id,starts_at,ends_at) values(p_business,(p_data->>'resource_id')::uuid,(p_data->>'starts_at')::timestamptz,(p_data->>'starts_at')::timestamptz+make_interval(mins=>(p_data->>'minutes')::integer));
  elsif p_action='remove_break' then
    delete from private.resource_breaks where id=(p_data->>'id')::uuid and business_id=p_business;
  elsif p_action='close' then
    if exists(select 1 from public.visits where business_id=p_business and status in ('booked','waiting','serving')) then raise exception 'Finish or cancel active visits first'; end if;
    update public.businesses set status='closed',queue_open=false where id=p_business;
  else raise exception 'Unknown business action';
  end if;
  insert into private.audit(actor_id,action,subject_id) values(auth.uid(),'business_'||p_action,p_business);
end $$;

-- Arrival is separate from service/queue status. Existing estimates remain intact.
alter table public.visits add column checked_in_at timestamptz;
create function public.check_in_visit(p_visit uuid) returns void
language plpgsql security definer set search_path='' as $$
declare b uuid; changed integer;
begin
  select business_id into b from public.visits where id=p_visit;
  if b is null then raise exception 'Visit not found'; end if;
  perform private.require_operator(b);
  perform pg_advisory_xact_lock(hashtextextended(b::text,0));
  if not exists(select 1 from public.visits where id=p_visit and status in ('waiting','booked')) then raise exception 'This visit cannot be checked in'; end if;
  update public.visits set checked_in_at=now() where id=p_visit and checked_in_at is null;
  get diagnostics changed=row_count;
  if changed>0 then insert into private.audit(actor_id,action,subject_id) values(auth.uid(),'visit_checked_in',p_visit); end if;
end $$;
revoke all on function public.check_in_visit(uuid) from public,anon;
grant execute on function public.check_in_visit(uuid) to authenticated;
