-- Chairside: authoritative booking rules. All times are stored as timestamptz.
create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.admins (user_id uuid primary key references auth.users on delete cascade);
create table private.blocked_users (user_id uuid primary key references auth.users on delete cascade);
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default '' check (length(display_name) <= 80),
  sms_updates boolean not null default false,
  marketing_consent boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users,
  name text not null check (length(name) between 2 and 100),
  kind text not null check (kind in ('barber','salon','home')),
  description text not null default '' check (length(description) <= 2000),
  status text not null default 'pending' check (status in ('pending','approved','rejected','suspended','closed')),
  review_note text not null default '',
  suburb text not null check (length(suburb) between 2 and 100),
  public_lat double precision not null check(public_lat between -48 and -33),
  public_lng double precision not null check(public_lng between 165 and 180),
  place_id text check(length(place_id) <= 250),
  timezone text not null default 'Pacific/Auckland' check(timezone = 'Pacific/Auckland'),
  publish_consent boolean not null default false,
  queue_open boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index one_open_business_per_owner on public.businesses(owner_id) where status <> 'closed';
create unique index one_approved_place on public.businesses(place_id) where status = 'approved' and place_id is not null;
create table private.business_locations (
  business_id uuid primary key references public.businesses on delete cascade,
  address text not null check(length(address) between 5 and 300),
  lat double precision not null check(lat between -48 and -33),
  lng double precision not null check(lng between 165 and 180)
);
create table private.payment_accounts (
  business_id uuid primary key references public.businesses,
  stripe_account text unique,
  charges_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
create table public.resources (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses on delete cascade,
  name text not null check(length(name) between 1 and 80),
  active boolean not null default true
);
create table public.services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses on delete cascade,
  name text not null check(length(name) between 2 and 100),
  minutes integer not null check(minutes between 10 and 240),
  price_cents integer not null check(price_cents between 100 and 200000),
  active boolean not null default true
);
create table public.hours (
  business_id uuid not null references public.businesses on delete cascade,
  weekday integer not null check(weekday between 1 and 7),
  opens time not null,
  closes time not null,
  primary key(business_id, weekday),
  check(opens < closes)
);
create table private.resource_breaks (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses,
  resource_id uuid not null references public.resources,
  starts_at timestamptz not null, ends_at timestamptz not null,
  check(ends_at>starts_at)
);
create table public.visits (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses,
  resource_id uuid not null references public.resources,
  service_id uuid not null references public.services,
  customer_id uuid references auth.users on delete set null,
  customer_name text not null check(length(customer_name) between 1 and 80),
  service_name text not null,
  minutes integer not null,
  price_cents integer not null,
  kind text not null check(kind in ('appointment','queue')),
  status text not null check(status in ('booked','waiting','serving','completed','cancelled','no_show')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  payment_status text not null default 'unpaid' check(payment_status in ('unpaid','paid','refund_pending','refunded')),
  check(ends_at > starts_at),
  exclude using gist(resource_id with =, tstzrange(starts_at,ends_at,'[)') with &&)
    where(status in ('booked','serving'))
);
create unique index one_active_visit on public.visits(customer_id) where customer_id is not null and status in ('booked','waiting','serving');
create index visits_business_time on public.visits(business_id, starts_at);
create index visits_customer on public.visits(customer_id, created_at desc);
create index queue_order on public.visits(resource_id, created_at, id) where status='waiting';
create table private.visit_contacts (
  visit_id uuid primary key references public.visits on delete cascade,
  phone text not null check(phone ~ '^\+[1-9][0-9]{7,14}$'),
  sms_consent boolean not null default false
);
create table public.favorites (
  customer_id uuid not null references auth.users on delete cascade,
  business_id uuid not null references public.businesses on delete cascade,
  primary key(customer_id,business_id)
);
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users,
  business_id uuid not null references public.businesses,
  message text not null check(length(message) between 10 and 2000),
  status text not null default 'open' check(status in ('open','resolved')),
  created_at timestamptz not null default now()
);
create table private.audit (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  subject_id uuid,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create table private.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null references public.visits on delete cascade,
  kind text not null check(kind in ('confirmation','reminder','next','cancelled')),
  due_at timestamptz not null default now(),
  state text not null default 'pending' check(state in ('pending','sending','sent','failed','skipped')),
  attempts integer not null default 0,
  lease_until timestamptz,
  provider_id text,
  last_error text,
  unique(visit_id,kind)
);
create table private.rate_limits (key text primary key, window_at timestamptz not null, count integer not null);

create function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.admins where user_id=auth.uid()) and coalesce(auth.jwt()->>'aal','')='aal2'
$$;
create function private.owns(p_business uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.businesses where id=p_business and owner_id=auth.uid())
$$;
create function private.is_public(p_business uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.businesses where id=p_business and status='approved' and publish_consent)
$$;
create function private.require_user() returns uuid language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and phone_confirmed_at is not null and deleted_at is null) or exists(select 1 from private.blocked_users where user_id=auth.uid()) then
    raise exception 'Please verify your phone number first';
  end if;
  return auth.uid();
end $$;
create function private.require_operator(p_business uuid) returns void language plpgsql stable security definer set search_path='' as $$
begin
  perform private.require_user();
  if not (private.owns(p_business) or private.is_admin()) then raise exception 'Business access denied'; end if;
  if coalesce(auth.jwt()->>'aal','') <> 'aal2' then raise exception 'Unlock business access with your authenticator'; end if;
end $$;

alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.resources enable row level security;
alter table public.services enable row level security;
alter table public.hours enable row level security;
alter table public.visits enable row level security;
alter table public.favorites enable row level security;
alter table public.reports enable row level security;
-- Policies never trust user-editable metadata. Sensitive mutations use the RPCs below.
create policy own_profile_read on public.profiles for select to authenticated using(id=auth.uid());
create policy own_profile_insert on public.profiles for insert to authenticated with check(id=auth.uid());
create policy own_profile_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy business_private_read on public.businesses for select to authenticated using((private.owns(id) and auth.jwt()->>'aal'='aal2') or private.is_admin());
create policy resources_read on public.resources for select using(private.is_public(business_id) or private.owns(business_id) or private.is_admin());
create policy services_read on public.services for select using(private.is_public(business_id) or private.owns(business_id) or private.is_admin());
create policy hours_read on public.hours for select using(private.is_public(business_id) or private.owns(business_id) or private.is_admin());
create policy visit_read on public.visits for select to authenticated using(customer_id=auth.uid() or (private.owns(business_id) and auth.jwt()->>'aal'='aal2') or private.is_admin());
create policy favorite_read on public.favorites for select to authenticated using(customer_id=auth.uid());
create policy favorite_add on public.favorites for insert to authenticated with check(customer_id=auth.uid());
create policy favorite_remove on public.favorites for delete to authenticated using(customer_id=auth.uid());
create policy report_read on public.reports for select to authenticated using(user_id=auth.uid() or private.is_admin());
create policy report_create on public.reports for insert to authenticated with check(user_id=auth.uid() and length(message) between 10 and 2000);
grant usage on schema private to authenticated, anon;
grant execute on function private.is_admin(), private.owns(uuid) to authenticated, anon;
grant select on public.businesses, public.resources, public.services, public.hours, public.visits, public.profiles, public.reports, public.favorites to authenticated;
grant select on public.resources, public.services, public.hours to anon;
grant insert,update on public.profiles to authenticated;
grant insert,delete on public.favorites to authenticated;
grant insert on public.reports to authenticated;
-- Supabase's default grants may be broader; remove all direct business/visit writes explicitly.
revoke insert,update,delete on public.businesses,public.resources,public.services,public.hours,public.visits from anon,authenticated;
revoke all on all tables in schema private from anon,authenticated;

create function public.account_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=private.require_user();
begin
  return jsonb_build_object('is_admin',exists(select 1 from private.admins where user_id=u),
    'business_id',(select id from public.businesses where owner_id=u and status<>'closed'),
    'aal2',auth.jwt()->>'aal'='aal2');
end $$;

-- Only public coordinates participate in discovery. Exact home coordinates cannot be probed.
create function public.discover_businesses(p_lat double precision, p_lng double precision, p_radius_km double precision default 25)
returns table(id uuid,name text,kind text,description text,suburb text,lat double precision,lng double precision,place_id text,queue_open boolean,distance_km double precision)
language sql stable security definer set search_path='' as $$
  select b.id,b.name,b.kind,b.description,b.suburb,b.public_lat,b.public_lng,b.place_id,b.queue_open,
    6371*2*asin(sqrt(least(1.0,power(sin(radians(b.public_lat-p_lat)/2),2)+cos(radians(p_lat))*cos(radians(b.public_lat))*power(sin(radians(b.public_lng-p_lng)/2),2)))) as distance_km
  from public.businesses b where b.status='approved' and b.publish_consent
    and p_lat between -48 and -33 and p_lng between 165 and 180
    and 6371*2*asin(sqrt(least(1.0,power(sin(radians(b.public_lat-p_lat)/2),2)+cos(radians(p_lat))*cos(radians(b.public_lat))*power(sin(radians(b.public_lng-p_lng)/2),2)))) <= least(greatest(p_radius_km,1),100)
  order by distance_km limit 100
$$;
create function public.business_detail(p_business uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare b public.businesses; result jsonb;
begin
  select * into b from public.businesses where id=p_business and ((status='approved' and publish_consent) or private.owns(id) or private.is_admin());
  if b.id is null then raise exception 'Business unavailable'; end if;
  result:=jsonb_build_object('id',b.id,'name',b.name,'kind',b.kind,'description',b.description,'suburb',b.suburb,'lat',b.public_lat,'lng',b.public_lng,'queue_open',b.queue_open,'status',b.status,
    'services',coalesce((select jsonb_agg(s order by s.name) from public.services s where business_id=b.id and active),'[]'),
    'resources',coalesce((select jsonb_agg(r order by r.name) from public.resources r where business_id=b.id and active),'[]'),
    'hours',coalesce((select jsonb_agg(h order by h.weekday) from public.hours h where business_id=b.id),'[]'),
    'online_payments',coalesce((select charges_enabled from private.payment_accounts where business_id=b.id),false));
  return result;
end $$;
create function public.apply_business(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); b uuid; k text:=p_data->>'kind'; la double precision:=(p_data->>'lat')::double precision; lo double precision:=(p_data->>'lng')::double precision;
begin
  if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'Set up your authenticator before applying'; end if;
  if coalesce((p_data->>'publish_consent')::boolean,false)=false then raise exception 'Consent to publish your listing is required'; end if;
  if coalesce((p_data->>'operating_declaration')::boolean,false)=false then raise exception 'Confirm your authority and operating permissions'; end if;
  insert into public.businesses(owner_id,name,kind,description,suburb,public_lat,public_lng,place_id,publish_consent)
  values(u,trim(p_data->>'name'),k,coalesce(p_data->>'description',''),trim(p_data->>'suburb'),
    case when k='home' then round(la::numeric,2)::double precision else la end,
    case when k='home' then round(lo::numeric,2)::double precision else lo end,
    nullif(p_data->>'place_id',''),true) returning id into b;
  insert into private.business_locations values(b,trim(p_data->>'address'),la,lo);
  insert into public.resources(business_id,name) values(b,'Chair 1');
  insert into private.audit(actor_id,action,subject_id,details) values(u,'business_applied',b,jsonb_build_object('operating_declaration',true,'publish_consent',true));
  return b;
end $$;
create function public.operator_business(p_business uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform private.require_operator(p_business);
  return (select to_jsonb(b)||jsonb_build_object('location',to_jsonb(l),'services',coalesce((select jsonb_agg(s order by s.name) from public.services s where business_id=b.id),'[]'),
    'resources',coalesce((select jsonb_agg(r order by r.name) from public.resources r where business_id=b.id),'[]'),
    'hours',coalesce((select jsonb_agg(h order by weekday) from public.hours h where business_id=b.id),'[]'),
    'online_payments',coalesce((select charges_enabled from private.payment_accounts where business_id=b.id),false),
    'breaks',coalesce((select jsonb_agg(rb order by rb.starts_at) from private.resource_breaks rb where business_id=b.id and ends_at>now()),'[]'))
    from public.businesses b join private.business_locations l on l.business_id=b.id where b.id=p_business);
end $$;
create function public.configure_business(p_business uuid,p_action text,p_data jsonb default '{}') returns void language plpgsql security definer set search_path='' as $$
declare v uuid; item jsonb;
begin
  perform private.require_operator(p_business);
  perform pg_advisory_xact_lock(hashtextextended(p_business::text,0));
  if p_action='queue' then
    if exists(select 1 from public.businesses where id=p_business and kind='home') and (p_data->>'open')::boolean then raise exception 'Home studios accept appointments only'; end if;
    update public.businesses set queue_open=(p_data->>'open')::boolean where id=p_business;
  elsif p_action='service' then
    if nullif(p_data->>'id','') is null then
      insert into public.services(business_id,name,minutes,price_cents) values(p_business,p_data->>'name',(p_data->>'minutes')::integer,(p_data->>'price_cents')::integer);
    else
      update public.services set name=p_data->>'name',minutes=(p_data->>'minutes')::integer,price_cents=(p_data->>'price_cents')::integer,active=coalesce((p_data->>'active')::boolean,true) where id=(p_data->>'id')::uuid and business_id=p_business;
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

-- Pure interval predicate, callable only by trusted functions.
create function private.slot_free(p_resource uuid,p_start timestamptz,p_minutes integer,p_exclude uuid default null,p_include_queue boolean default true) returns boolean
language sql stable security definer set search_path='' as $$
  select p_start >= now()-interval '2 minutes' and p_start < now()+interval '90 days'
  and exists(select 1 from public.resources r join public.businesses b on b.id=r.business_id
    join public.hours h on h.business_id=b.id and h.weekday=extract(isodow from p_start at time zone b.timezone)
    where r.id=p_resource and r.active
    and (p_start at time zone b.timezone)::date=((p_start+make_interval(mins=>p_minutes)) at time zone b.timezone)::date
    and (p_start at time zone b.timezone)::time>=h.opens
    and ((p_start+make_interval(mins=>p_minutes)) at time zone b.timezone)::time<=h.closes)
  and not exists(select 1 from private.resource_breaks rb where resource_id=p_resource and tstzrange(rb.starts_at,rb.ends_at,'[)') && tstzrange(p_start,p_start+make_interval(mins=>p_minutes),'[)'))
  and not exists(select 1 from public.visits v where resource_id=p_resource and (p_exclude is null or id<>p_exclude)
    and (status in ('booked','serving') or (p_include_queue and status='waiting'))
    and tstzrange(starts_at,ends_at,'[)') && tstzrange(p_start,p_start+make_interval(mins=>p_minutes),'[)'))
$$;
create function public.available_slots(p_business uuid,p_service uuid,p_day date) returns table(resource_id uuid,resource_name text,starts_at timestamptz)
language sql stable security definer set search_path='' as $$
  select r.id,r.name,t.slot from public.businesses b join public.resources r on r.business_id=b.id and r.active
  join public.services s on s.business_id=b.id and s.id=p_service and s.active
  join public.hours h on h.business_id=b.id and h.weekday=extract(isodow from p_day)
  cross join lateral generate_series((p_day+h.opens) at time zone b.timezone,(p_day+h.closes) at time zone b.timezone-make_interval(mins=>s.minutes),interval '15 minutes') t(slot)
  where b.id=p_business and b.status='approved' and b.publish_consent and t.slot>now()+interval '5 minutes'
    and p_day between (now() at time zone b.timezone)::date and (now() at time zone b.timezone)::date+89
    and private.slot_free(r.id,t.slot,s.minutes)
  order by t.slot,r.name limit 500
$$;
create function private.reflow_queue(p_resource uuid) returns void language plpgsql security definer set search_path='' as $$
declare v public.visits; candidate timestamptz:=date_trunc('minute',clock_timestamp())+interval '1 minute'; attempts integer;
begin
  for v in select * from public.visits where resource_id=p_resource and status='waiting' order by created_at,id loop
    attempts:=0;
    while not private.slot_free(p_resource,candidate,v.minutes,v.id,false) loop
      candidate:=candidate+interval '1 minute'; attempts:=attempts+1;
      -- A queue is for today's opening session, never roll somebody into tomorrow.
      if attempts>1440 or (candidate at time zone 'Pacific/Auckland')::date<>(now() at time zone 'Pacific/Auckland')::date then
        raise exception 'No more queue capacity today';
      end if;
    end loop;
    update public.visits set starts_at=candidate,ends_at=candidate+make_interval(mins=>v.minutes) where id=v.id;
    candidate:=candidate+make_interval(mins=>v.minutes);
  end loop;
end $$;
create function public.create_visit(p_business uuid,p_service uuid,p_resource uuid,p_kind text,p_start timestamptz default null,p_walk_in jsonb default null) returns uuid
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
    select au.phone into phone from auth.users au where au.id=u;
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
  if p_kind='appointment' then insert into private.notification_outbox(visit_id,kind,due_at) values(vid,'reminder',greatest(now(),p_start-interval '1 hour')); end if;
  return vid;
exception when unique_violation then raise exception 'You already have an active visit, or that slot was just taken. Refresh and try again';
  when exclusion_violation then raise exception 'That slot was just taken. Choose another time';
end $$;
create function public.change_visit(p_visit uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); v public.visits; operator boolean;
begin
  select * into v from public.visits where id=p_visit;
  if v.id is null then raise exception 'Visit not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v.business_id::text,0));
  select * into v from public.visits where id=p_visit for update;
  operator:=private.owns(v.business_id) or private.is_admin();
  if operator then perform private.require_operator(v.business_id); end if;
  if p_action='cancel' then
    if not operator and v.customer_id is distinct from u then raise exception 'Visit access denied'; end if;
    if v.status not in ('waiting','booked') then raise exception 'Only upcoming visits can be cancelled'; end if;
    update public.visits set status='cancelled',payment_status=case when payment_status='paid' then 'refund_pending' else payment_status end where id=v.id;
    insert into private.notification_outbox(visit_id,kind) values(v.id,'cancelled') on conflict do nothing;
  else
    if not operator then raise exception 'Business access denied'; end if;
    if p_action='start' then
      if v.status not in ('booked','waiting') then raise exception 'Visit cannot be started'; end if;
      if exists(select 1 from public.visits where resource_id=v.resource_id and status='serving') then raise exception 'Finish the current visit first'; end if;
      if v.status='waiting' and exists(select 1 from public.visits where resource_id=v.resource_id and status='waiting' and (created_at,id)<(v.created_at,v.id)) then raise exception 'Serve the first person in this chair’s queue'; end if;
      if v.kind='appointment' and v.starts_at>now()+interval '5 minutes' then raise exception 'This appointment is too early to start'; end if;
      if not private.slot_free(v.resource_id,now(),v.minutes,v.id,false) then raise exception 'Not enough time before the next appointment or closing'; end if;
      update public.visits set status='serving',starts_at=now(),ends_at=now()+make_interval(mins=>v.minutes) where id=v.id;
    elsif p_action='complete' then
      if v.status<>'serving' then raise exception 'Start this visit before completing it'; end if;
      update public.visits set status='completed',completed_at=now() where id=v.id;
    elsif p_action='no_show' then
      if v.status not in ('booked','waiting') or v.starts_at>now() then raise exception 'Only overdue upcoming visits can be marked absent'; end if;
      update public.visits set status='no_show',payment_status=case when payment_status='paid' then 'refund_pending' else payment_status end where id=v.id;
    else raise exception 'Unknown visit action'; end if;
  end if;
  -- If delays remove all remaining capacity, keep existing estimates instead of losing the operation.
  begin perform private.reflow_queue(v.resource_id); exception when raise_exception then null; end;
  insert into private.audit(actor_id,action,subject_id) values(u,'visit_'||p_action,v.id);
end $$;
create function public.visit_location(p_visit uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v public.visits;
begin
  perform private.require_user(); select * into v from public.visits where id=p_visit;
  if not coalesce(((v.customer_id=auth.uid() and v.status in ('booked','waiting','serving')) or (private.owns(v.business_id) and auth.jwt()->>'aal'='aal2') or private.is_admin()),false) then raise exception 'Address access denied'; end if;
  return (select to_jsonb(l)-'business_id' from private.business_locations l where business_id=v.business_id);
end $$;
create function public.admin_overview() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_admin() then raise exception 'Admin access denied; verify your authenticator'; end if;
  return jsonb_build_object('businesses',coalesce((select jsonb_agg(to_jsonb(b)||jsonb_build_object('location',to_jsonb(l),'owner_phone',(select phone from auth.users where id=b.owner_id)) order by b.created_at desc) from public.businesses b join private.business_locations l on l.business_id=b.id),'[]'),
    'reports',coalesce((select jsonb_agg(r order by r.created_at desc) from public.reports r where status='open'),'[]'));
end $$;
create function public.admin_review(p_business uuid,p_status text,p_note text) returns void language plpgsql security definer set search_path='' as $$
begin
  if not private.is_admin() then raise exception 'Admin access denied'; end if;
  if p_status not in ('approved','rejected','suspended') or length(p_note) not between 10 and 2000 then raise exception 'Add a review note of 10–2000 characters'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_business::text,0));
  if p_status='approved' and (not exists(select 1 from public.services where business_id=p_business and active) or not exists(select 1 from public.hours where business_id=p_business)) then raise exception 'Provider must add services and opening hours before approval'; end if;
  update public.businesses set status=p_status,review_note=p_note,queue_open=case when p_status='approved' then queue_open else false end where id=p_business and status<>'closed';
  if not found then raise exception 'Business not found'; end if;
  insert into private.audit(actor_id,action,subject_id,details) values(auth.uid(),'admin_review',p_business,jsonb_build_object('status',p_status,'note',p_note));
end $$;
create function public.resolve_report(p_report uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  if not private.is_admin() then raise exception 'Admin access denied'; end if;
  update public.reports set status='resolved' where id=p_report;
  insert into private.audit(actor_id,action,subject_id) values(auth.uid(),'resolve_report',p_report);
end $$;

-- Explicit function grants: PostgreSQL otherwise grants execution to PUBLIC.
revoke execute on all functions in schema private from public,anon,authenticated;
grant execute on function private.is_admin(),private.owns(uuid),private.is_public(uuid) to anon,authenticated;
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.discover_businesses(double precision,double precision,double precision),public.business_detail(uuid),public.available_slots(uuid,uuid,date) to anon,authenticated;
grant execute on function public.account_context(),public.apply_business(jsonb),public.operator_business(uuid),public.configure_business(uuid,text,jsonb),public.create_visit(uuid,uuid,uuid,text,timestamptz,jsonb),public.change_visit(uuid,text),public.visit_location(uuid),public.admin_overview(),public.admin_review(uuid,text,text),public.resolve_report(uuid) to authenticated;

-- Realtime carries only RLS-filtered visit records. No private address/phone publication.
do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    alter publication supabase_realtime add table public.visits;
  end if;
end $$;
