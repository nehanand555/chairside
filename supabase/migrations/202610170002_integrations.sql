create table private.checkout_sessions (
  id uuid primary key default gen_random_uuid(), visit_id uuid not null references public.visits,
  stripe_id text unique, url text, expires_at timestamptz not null default now()+interval '31 minutes',
  amount integer not null, state text not null default 'open' check(state in ('open','paid','expired'))
);
create table private.payments (
  visit_id uuid primary key references public.visits,
  payment_intent text not null unique, amount integer not null, refund_id text,
  created_at timestamptz not null default now()
);
create table private.stripe_events (id text primary key, created_at timestamptz not null default now());

create function public.integration_limit(p_key text,p_max integer,p_seconds integer) returns boolean language plpgsql security definer set search_path='' as $$
declare n integer;
begin
  insert into private.rate_limits values(p_key,now(),1) on conflict(key) do update
    set window_at=case when private.rate_limits.window_at<now()-make_interval(secs=>p_seconds) then now() else private.rate_limits.window_at end,
        count=case when private.rate_limits.window_at<now()-make_interval(secs=>p_seconds) then 1 else private.rate_limits.count+1 end returning count into n;
  delete from private.rate_limits where window_at<now()-interval '2 days';
  return n<=p_max;
end $$;
create function public.integration_account(p_business uuid,p_account text default null,p_enabled boolean default null) returns jsonb language plpgsql security definer set search_path='' as $$
begin
  insert into private.payment_accounts(business_id,stripe_account,charges_enabled) values(p_business,p_account,coalesce(p_enabled,false))
    on conflict(business_id) do update set stripe_account=coalesce(excluded.stripe_account,private.payment_accounts.stripe_account),charges_enabled=coalesce(p_enabled,private.payment_accounts.charges_enabled),updated_at=now();
  return (select to_jsonb(a) from private.payment_accounts a where business_id=p_business);
end $$;
create function public.integration_checkout(p_user uuid,p_visit uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.visits; a private.payment_accounts; c private.checkout_sessions;
begin
  select * into v from public.visits where id=p_visit for update;
  if v.customer_id is distinct from p_user or v.status not in ('booked','waiting') then raise exception 'Only your upcoming visit can be paid'; end if;
  if v.payment_status<>'unpaid' then raise exception 'This visit has already been paid'; end if;
  select * into a from private.payment_accounts where business_id=v.business_id;
  if not coalesce(a.charges_enabled,false) then raise exception 'Online payments are not available for this business'; end if;
  update private.checkout_sessions set state='expired' where visit_id=v.id and expires_at<now() and state='open';
  select * into c from private.checkout_sessions where visit_id=v.id and state='open' order by expires_at desc limit 1;
  if c.id is null then
    insert into private.checkout_sessions(visit_id,amount) values(v.id,v.price_cents) returning * into c;
  end if;
  return to_jsonb(c)||jsonb_build_object('account',a.stripe_account,'service_name',v.service_name,'kind',v.kind,'starts_at',v.starts_at);
end $$;
create function public.integration_sync_account(p_account text,p_enabled boolean) returns void language sql security definer set search_path='' as $$
  update private.payment_accounts set charges_enabled=p_enabled,updated_at=now() where stripe_account=p_account
$$;
create function public.integration_refund_event(p_intent text,p_refund text,p_amount integer) returns void language sql security definer set search_path='' as $$
  update public.visits set payment_status='refunded' where id in(select visit_id from private.payments where payment_intent=p_intent and amount=p_amount)
$$;
create function public.integration_checkout_saved(p_id uuid,p_stripe text,p_url text) returns void language sql security definer set search_path='' as $$
  update private.checkout_sessions set stripe_id=p_stripe,url=p_url where id=p_id and state='open'
$$;
create function public.integration_paid(p_event text,p_session uuid,p_intent text,p_amount integer,p_currency text) returns void language plpgsql security definer set search_path='' as $$
declare c private.checkout_sessions; v public.visits;
begin
  insert into private.stripe_events(id) values(p_event) on conflict do nothing;
  if not found then return; end if;
  select * into c from private.checkout_sessions where id=p_session for update;
  if c.id is null or c.amount<>p_amount or p_currency<>'nzd' then raise exception 'Payment amount or currency mismatch'; end if;
  select * into v from public.visits where id=c.visit_id for update;
  if exists(select 1 from private.payments where visit_id=v.id and payment_intent<>p_intent) then raise exception 'Unexpected duplicate payment: manual review needed'; end if;
  insert into private.payments(visit_id,payment_intent,amount) values(v.id,p_intent,p_amount) on conflict(visit_id) do nothing;
  update private.checkout_sessions set state='paid' where id=c.id;
  update public.visits set payment_status=case when status in ('cancelled','no_show') then 'refund_pending' else 'paid' end where id=v.id and payment_status='unpaid';
end $$;
create function public.integration_refunds() returns jsonb language sql security definer set search_path='' as $$
  select coalesce(jsonb_agg(x),'[]') from (select p.visit_id,p.payment_intent,p.amount from private.payments p join public.visits v on v.id=p.visit_id where v.payment_status='refund_pending' and p.refund_id is null limit 30) x
$$;
create function public.integration_refunded(p_visit uuid,p_refund text,p_complete boolean) returns void language plpgsql security definer set search_path='' as $$
begin
  update private.payments set refund_id=p_refund where visit_id=p_visit;
  if p_complete then update public.visits set payment_status='refunded' where id=p_visit; end if;
end $$;
create function public.request_refund(p_visit uuid) returns void language plpgsql security definer set search_path='' as $$
declare v public.visits;
begin
  select * into v from public.visits where id=p_visit for update;
  perform private.require_operator(v.business_id);
  if v.payment_status<>'paid' then raise exception 'Only a paid visit can be refunded'; end if;
  update public.visits set payment_status='refund_pending' where id=p_visit;
  insert into private.audit(actor_id,action,subject_id) values(auth.uid(),'refund_requested',p_visit);
end $$;
create function public.integration_claim_messages() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  -- Abandoned sends are ambiguous: do not automatically send a second chargeable SMS.
  update private.notification_outbox set state='failed',last_error='Send interrupted; delivery requires review' where state='sending' and lease_until<now();
  insert into private.notification_outbox(visit_id,kind)
    select id,'next' from public.visits where status='waiting' and starts_at<=now()+interval '10 minutes'
    on conflict do nothing;
  with picked as (select id from private.notification_outbox where state='pending' and due_at<=now() order by due_at for update skip locked limit 20),
  claimed as (update private.notification_outbox n set state='sending',attempts=attempts+1,lease_until=now()+interval '5 minutes' from picked where n.id=picked.id returning n.*)
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'kind',c.kind,'phone',vc.phone,'consent',coalesce(vc.sms_consent,false),'status',v.status,'business',b.name,'starts_at',v.starts_at)),'[]') into result
    from claimed c join public.visits v on v.id=c.visit_id join public.businesses b on b.id=v.business_id left join private.visit_contacts vc on vc.visit_id=v.id;
  return result;
end $$;
create function public.integration_message_done(p_id uuid,p_state text,p_provider text default null,p_error text default null) returns void language plpgsql security definer set search_path='' as $$
begin
  if p_state not in ('sent','skipped','failed') then raise exception 'Invalid delivery state'; end if;
  update private.notification_outbox set state=p_state,provider_id=p_provider,last_error=left(p_error,200),lease_until=null where id=p_id and state='sending';
end $$;
create function public.integration_delete_user(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user::text,42));
  if exists(select 1 from private.admins where user_id=p_user) then raise exception 'Transfer administration before deleting this account'; end if;
  if exists(select 1 from public.businesses where owner_id=p_user and status<>'closed') then raise exception 'Close your business in Business settings first'; end if;
  if exists(select 1 from public.visits where customer_id=p_user and (status in ('booked','waiting','serving') or payment_status='refund_pending')) then raise exception 'Finish or cancel visits and wait for pending refunds before deleting your account'; end if;
  if exists(select 1 from public.visits v join public.businesses b on b.id=v.business_id where b.owner_id=p_user and v.payment_status='refund_pending') then raise exception 'Wait for business refunds before deleting your account'; end if;
  insert into private.blocked_users values(p_user) on conflict do nothing;
  -- Preserve financial history without personal customer identifiers.
  delete from private.visit_contacts where visit_id in(select id from public.visits where customer_id=p_user);
  update public.visits set customer_name='Deleted customer',customer_id=null where customer_id=p_user;
  delete from public.reports where user_id=p_user;
  delete from public.favorites where customer_id=p_user;
  delete from public.profiles where id=p_user;
  -- Closed businesses retain a legal owner reference; a dedicated tombstone auth record is unnecessary.
  -- Owner auth records are soft-deleted by the Edge function, preventing sign-in.
end $$;
revoke execute on function public.request_refund(uuid) from public,anon;
grant execute on function public.request_refund(uuid) to authenticated;
revoke execute on function public.integration_limit(text,integer,integer),public.integration_account(uuid,text,boolean),public.integration_checkout(uuid,uuid),public.integration_checkout_saved(uuid,text,text),public.integration_paid(text,uuid,text,integer,text),public.integration_refunds(),public.integration_refunded(uuid,text,boolean),public.integration_claim_messages(),public.integration_message_done(uuid,text,text,text),public.integration_delete_user(uuid) from public,anon,authenticated;
grant execute on function public.integration_limit(text,integer,integer),public.integration_account(uuid,text,boolean),public.integration_checkout(uuid,uuid),public.integration_checkout_saved(uuid,text,text),public.integration_paid(text,uuid,text,integer,text),public.integration_refunds(),public.integration_refunded(uuid,text,boolean),public.integration_claim_messages(),public.integration_message_done(uuid,text,text,text),public.integration_delete_user(uuid) to service_role;
revoke all on all tables in schema private from public,anon,authenticated;
revoke execute on function public.integration_sync_account(text,boolean),public.integration_refund_event(text,text,integer) from public,anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('portfolios','portfolios',true,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy portfolio_read on storage.objects for select using(bucket_id='portfolios');
create policy portfolio_insert on storage.objects for insert to authenticated with check(bucket_id='portfolios' and auth.jwt()->>'aal'='aal2' and private.owns((storage.foldername(name))[1]::uuid));
create policy portfolio_delete on storage.objects for delete to authenticated using(bucket_id='portfolios' and auth.jwt()->>'aal'='aal2' and private.owns((storage.foldername(name))[1]::uuid));
grant execute on all functions in schema public to service_role;
