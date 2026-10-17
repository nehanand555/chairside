-- Refund events may arrive before Checkout's payment event. Persist them independently.
create table private.refunds_received (
  refund_id text primary key,payment_intent text not null,amount integer not null check(amount>0)
);
create index refunds_by_intent on private.refunds_received(payment_intent);
create function public.integration_match_checkout(p_id uuid,p_stripe text) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.checkout_sessions where id=p_id and stripe_id=p_stripe)
$$;
revoke execute on function public.integration_match_checkout(uuid,text) from public,anon,authenticated;
grant execute on function public.integration_match_checkout(uuid,text) to service_role;
create or replace function public.integration_paid(p_event text,p_session uuid,p_intent text,p_amount integer,p_currency text) returns void language plpgsql security definer set search_path='' as $$
declare c private.checkout_sessions;v public.visits;already_refunded boolean;
begin
  insert into private.stripe_events(id) values(p_event) on conflict do nothing;
  if not found then return; end if;
  select * into c from private.checkout_sessions where id=p_session;
  if c.id is null or c.amount<>p_amount or p_currency<>'nzd' then raise exception 'Payment amount or currency mismatch'; end if;
  -- Serialise payment/refund processing for this intent, including out-of-order delivery.
  perform pg_advisory_xact_lock(hashtextextended(p_intent,87));
  select * into v from public.visits where id=c.visit_id for update;
  already_refunded:=(select coalesce(sum(amount),0)>=p_amount from private.refunds_received where payment_intent=p_intent);
  if exists(select 1 from private.payments where visit_id=v.id and payment_intent<>p_intent) then
    insert into private.orphan_refunds(payment_intent,amount,completed) values(p_intent,p_amount,already_refunded) on conflict do nothing;
    update private.checkout_sessions set state='paid' where id=c.id;
    return;
  end if;
  insert into private.payments(visit_id,payment_intent,amount) values(v.id,p_intent,p_amount) on conflict(visit_id) do nothing;
  update private.checkout_sessions set state='paid' where id=c.id;
  update public.visits set payment_status=case when already_refunded then 'refunded' when status in ('cancelled','no_show') then 'refund_pending' else 'paid' end where id=v.id and payment_status='unpaid';
end $$;
-- Both event handlers lock the intent first; the row update below then obtains the visit lock.
create or replace function public.integration_refund_event(p_intent text,p_refund text,p_amount integer) returns void language plpgsql security definer set search_path='' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_intent,87));
  insert into private.refunds_received values(p_refund,p_intent,p_amount) on conflict do nothing;
  update public.visits set payment_status='refunded' where id in(select p.visit_id from private.payments p where p.payment_intent=p_intent and p.amount<=(select coalesce(sum(amount),0) from private.refunds_received where payment_intent=p_intent));
  update private.orphan_refunds o set refund_id=p_refund,completed=true where o.payment_intent=p_intent and o.amount<=(select coalesce(sum(amount),0) from private.refunds_received where payment_intent=p_intent);
end $$;

-- Jump directly past conflicting intervals instead of scanning every minute of a day.
create function private.next_queue_gap(p_resource uuid,p_minutes integer,p_after timestamptz) returns timestamptz language plpgsql stable security definer set search_path='' as $$
declare opening timestamptz;closing timestamptz;candidate timestamptz;blocked_until timestamptz;attempt integer;
begin
  select ((now() at time zone b.timezone)::date+h.opens) at time zone b.timezone,
         ((now() at time zone b.timezone)::date+h.closes) at time zone b.timezone into opening,closing
    from public.resources r join public.businesses b on b.id=r.business_id join public.hours h on h.business_id=b.id and h.weekday=extract(isodow from now() at time zone b.timezone)
    where r.id=p_resource and r.active;
  if opening is null then return null; end if;
  candidate:=greatest(p_after,opening);
  for attempt in 1..300 loop
    if candidate+make_interval(mins=>p_minutes)>closing then return null; end if;
    select max(finish) into blocked_until from (
      select case when status='serving' then greatest(ends_at,now()+interval '5 minutes') else ends_at end as finish
      from public.visits where resource_id=p_resource and status in ('booked','serving')
        and tstzrange(starts_at,case when status='serving' then greatest(ends_at,now()+interval '5 minutes') else ends_at end,'[)')&&tstzrange(candidate,candidate+make_interval(mins=>p_minutes),'[)')
      union all select ends_at from private.resource_breaks where resource_id=p_resource and tstzrange(starts_at,ends_at,'[)')&&tstzrange(candidate,candidate+make_interval(mins=>p_minutes),'[)')
    ) blocked;
    if blocked_until is null then return candidate; end if;
    candidate:=blocked_until;
  end loop;
  return null;
end $$;
create or replace function private.reflow_queue(p_resource uuid) returns void language plpgsql security definer set search_path='' as $$
declare v public.visits;candidate timestamptz:=date_trunc('minute',clock_timestamp())+interval '1 minute';
begin
  for v in select * from public.visits where resource_id=p_resource and status='waiting' order by created_at,id loop
    candidate:=private.next_queue_gap(p_resource,v.minutes,candidate);
    if candidate is null then raise exception 'No more queue capacity today'; end if;
    update public.visits set starts_at=candidate,ends_at=candidate+make_interval(mins=>v.minutes) where id=v.id and starts_at is distinct from candidate;
    candidate:=candidate+make_interval(mins=>v.minutes);
  end loop;
end $$;
create function public.queue_estimates(p_business uuid,p_service uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb:='[]';r public.resources;v public.visits;candidate timestamptz;duration integer;n integer;
begin
  if not exists(select 1 from public.businesses where id=p_business and status='approved' and publish_consent and queue_open and kind<>'home') then return result; end if;
  select minutes into duration from public.services where id=p_service and business_id=p_business and active;
  if duration is null then return result; end if;
  for r in select * from public.resources where business_id=p_business and active order by name loop
    candidate:=date_trunc('minute',now())+interval '1 minute';
    select count(*) into n from public.visits where resource_id=r.id and status='waiting';
    for v in select * from public.visits where resource_id=r.id and status='waiting' order by created_at,id loop
      candidate:=private.next_queue_gap(r.id,v.minutes,candidate);
      if candidate is null then exit; end if;
      candidate:=candidate+make_interval(mins=>v.minutes);
    end loop;
    if candidate is not null then candidate:=private.next_queue_gap(r.id,duration,candidate); end if;
    result:=result||jsonb_build_array(jsonb_build_object('resource_id',r.id,'name',r.name,'waiting',n,'starts_at',candidate,'wait_minutes',case when candidate is not null then greatest(0,ceil(extract(epoch from candidate-now())/60)) else null end));
  end loop;
  return result;
end $$;
revoke execute on function private.next_queue_gap(uuid,integer,timestamptz),public.queue_estimates(uuid,uuid) from public,anon,authenticated;
grant execute on function public.queue_estimates(uuid,uuid) to anon,authenticated,service_role;
revoke all on private.refunds_received from public,anon,authenticated;

create or replace function public.integration_refunded(p_visit uuid,p_refund text,p_complete boolean) returns void language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.visits where id=p_visit for update;
  update private.payments set refund_id=p_refund where visit_id=p_visit;
  if p_complete then update public.visits set payment_status='refunded' where id=p_visit; end if;
end $$;
