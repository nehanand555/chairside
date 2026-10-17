-- A rare duplicate/late payment is refunded automatically without changing the original receipt.
create table private.orphan_refunds (
  payment_intent text primary key, amount integer not null,
  refund_id text, completed boolean not null default false,
  created_at timestamptz not null default now()
);
create or replace function public.integration_paid(p_event text,p_session uuid,p_intent text,p_amount integer,p_currency text) returns void language plpgsql security definer set search_path='' as $$
declare c private.checkout_sessions;v public.visits;
begin
  insert into private.stripe_events(id) values(p_event) on conflict do nothing;
  if not found then return; end if;
  -- Match the visit's lock order used by cancellation/refund to avoid cross-session deadlocks.
  select * into c from private.checkout_sessions where id=p_session;
  if c.id is null or c.amount<>p_amount or p_currency<>'nzd' then raise exception 'Payment amount or currency mismatch'; end if;
  select * into v from public.visits where id=c.visit_id for update;
  if exists(select 1 from private.payments where visit_id=v.id and payment_intent<>p_intent) then
    insert into private.orphan_refunds(payment_intent,amount) values(p_intent,p_amount) on conflict do nothing;
    update private.checkout_sessions set state='paid' where id=c.id;
    return;
  end if;
  insert into private.payments(visit_id,payment_intent,amount) values(v.id,p_intent,p_amount) on conflict(visit_id) do nothing;
  update private.checkout_sessions set state='paid' where id=c.id;
  update public.visits set payment_status=case when status in ('cancelled','no_show') then 'refund_pending' else 'paid' end where id=v.id and payment_status='unpaid';
end $$;
create or replace function public.integration_refunds() returns jsonb language sql security definer set search_path='' as $$
  select coalesce(jsonb_agg(x),'[]') from (
    select p.visit_id,p.payment_intent,p.amount from private.payments p join public.visits v on v.id=p.visit_id where v.payment_status='refund_pending' and p.refund_id is null
    union all select null::uuid,payment_intent,amount from private.orphan_refunds where not completed and refund_id is null
    limit 20
  ) x
$$;
create function public.integration_orphan_refunded(p_intent text,p_refund text,p_complete boolean) returns void language sql security definer set search_path='' as $$
  update private.orphan_refunds set refund_id=p_refund,completed=p_complete where payment_intent=p_intent
$$;
create or replace function public.integration_refund_event(p_intent text,p_refund text,p_amount integer) returns void language plpgsql security definer set search_path='' as $$
begin
  update public.visits set payment_status='refunded' where id in(select visit_id from private.payments where payment_intent=p_intent and amount=p_amount);
  update private.orphan_refunds set refund_id=p_refund,completed=true where payment_intent=p_intent and amount=p_amount;
end $$;

create or replace function private.require_user() returns uuid language plpgsql volatile security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and phone_confirmed_at is not null and deleted_at is null) or exists(select 1 from private.blocked_users where user_id=auth.uid()) then raise exception 'Please verify your phone number first'; end if;
  return auth.uid();
end $$;
create function private.before_visit_insert() returns trigger language plpgsql security definer set search_path='' as $$
declare key text;max_count integer;
begin
  if auth.uid() is not null then
    perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,42));
    perform private.require_user();
    key:=case when new.customer_id is null then 'walkin:'||new.business_id else 'booking:'||auth.uid() end;
    max_count:=case when new.customer_id is null then 500 else 10 end;
    if not public.integration_limit(key,max_count,86400) then raise exception 'Daily booking limit reached. Contact the business for help'; end if;
  end if;
  return new;
end $$;
create trigger visit_insert_guard before insert on public.visits for each row execute function private.before_visit_insert();
create function private.before_business_insert() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is not null then
    perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,42));
    perform private.require_user();
  end if;
  return new;
end $$;
create trigger business_insert_guard before insert on public.businesses for each row execute function private.before_business_insert();

create or replace function public.admin_health() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_admin() then raise exception 'Admin access denied'; end if;
  return jsonb_build_object('failed_sms',(select count(*) from private.notification_outbox where state='failed'),
    'pending_sms',(select count(*) from private.notification_outbox where state='pending' and due_at<now()-interval '5 minutes'),
    'pending_refunds',(select count(*) from public.visits where payment_status='refund_pending')+(select count(*) from private.orphan_refunds where not completed));
end $$;
revoke execute on function public.integration_orphan_refunded(text,text,boolean),private.before_visit_insert(),private.before_business_insert() from public,anon,authenticated;
grant execute on function public.integration_orphan_refunded(text,text,boolean) to service_role;
revoke all on all tables in schema private from public,anon,authenticated;
