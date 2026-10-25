
-- Transactional email outbox for business onboarding and review.
create table if not exists private.email_outbox (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 event_type text not null check (event_type in ('application_received','application_review','application_updated','decision_approved','decision_rejected','decision_suspended')),
 recipient text not null check (length(recipient) between 5 and 254),
 revision bigint not null,
 dedupe_key text not null unique,
 subject text not null,
 body text not null,
 state text not null default 'pending' check (state in ('pending','sending','accepted','delivered','bounced','failed','dead')),
 attempts integer not null default 0,
 next_attempt_at timestamptz not null default now(),
 lease_until timestamptz,
 provider_id text unique,
 error_code text,
 accepted_at timestamptz,
 delivered_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists email_outbox_due_idx on private.email_outbox(next_attempt_at) where state='pending';
create index if not exists email_outbox_business_idx on private.email_outbox(business_id,created_at desc);
revoke all on private.email_outbox from public, anon, authenticated;
grant select, insert, update on private.email_outbox to service_role;

create or replace function private.enqueue_business_email(p_business uuid,p_kind text,p_revision bigint,p_recipient text,p_subject text,p_body text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_recipient is null or length(trim(p_recipient)) not between 5 and 254 or trim(p_recipient) !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then return; end if;
 insert into private.email_outbox(business_id,event_type,revision,recipient,dedupe_key,subject,body)
 values(p_business,p_kind,p_revision,lower(trim(p_recipient)),p_business::text||':'||p_kind||':'||p_revision||':'||lower(trim(p_recipient)),p_subject,p_body)
 on conflict (dedupe_key) do nothing;
end $$;
revoke all on function private.enqueue_business_email(uuid,text,bigint,text,text,text) from public,anon,authenticated;

-- Application creation and revision are transactionally queued. Admin target is
-- resolved by the worker from APPLICATION_REVIEW_EMAIL, not from a public column.
create or replace function private.queue_application_emails() returns trigger
language plpgsql security definer set search_path='' as $$
declare r bigint; nm text; ev text;
begin
 select name into nm from public.businesses where id=new.business_id;
 r := case when tg_op='INSERT' then 1 else coalesce((select max(revision) from private.email_outbox where business_id=new.business_id and event_type in ('application_review','application_updated')),0)+1 end;
 ev := case when tg_op='INSERT' then 'application_review' else 'application_updated' end;
 perform private.enqueue_business_email(new.business_id,ev,r,'admin-routing@spicyself.invalid','SpicySelf application: '||nm,
 'Business: '||nm||E'\nApplication ID: '||new.business_id::text||E'\nContact: '||new.contact_name||E'\nEmail: '||new.contact_email||E'\nRegistration: '||new.registration_number||E'\nOpen the protected Admin portal to review.');
 if tg_op='INSERT' then
   perform private.enqueue_business_email(new.business_id,'application_received',r,new.contact_email,'SpicySelf application received',
   'Thanks for applying to SpicySelf. Your application for '||nm||' is saved and awaiting review. Reference: '||new.business_id::text);
 end if;
 return new;
end $$;
drop trigger if exists queue_business_application_email on private.business_applications;
create trigger queue_business_application_email after insert or update of registration_number,contact_name,contact_email,contact_phone on private.business_applications
for each row execute function private.queue_application_emails();

create or replace function private.queue_decision_email() returns trigger
language plpgsql security definer set search_path='' as $$
declare mail text; r bigint;
begin
 if old.status is distinct from new.status and new.status in ('approved','rejected','suspended') then
   select contact_email into mail from private.business_applications where business_id=new.id;
   r := (select coalesce(max(revision),0)+1 from private.email_outbox where business_id=new.id and event_type like 'decision_%');
   perform private.enqueue_business_email(new.id,'decision_'||new.status,r,mail,'SpicySelf business review: '||new.status,
   'The review of '||new.name||' is now '||new.status||'.'||E'\nReview note: '||coalesce(new.review_note,'')||
   E'\nSign in to SpicySelf to view your application.');
 end if;
 return new;
end $$;
drop trigger if exists queue_business_decision_email on public.businesses;
create trigger queue_business_decision_email after update of status on public.businesses
for each row execute function private.queue_decision_email();

-- Worker endpoints are service-role only; no user can claim or complete messages.
create or replace function public.email_claim_batch(p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if coalesce(auth.jwt()->>'role','') <> 'service_role' then raise exception 'Access denied'; end if;
 -- Ambiguous interrupted sends require reconciliation rather than blind resend.
 update private.email_outbox set state='failed',error_code='interrupted_ambiguous',lease_until=null,updated_at=now()
 where state='sending' and lease_until<now();
 with picked as (
  select id from private.email_outbox where state='pending' and next_attempt_at<=now()
  order by created_at for update skip locked limit least(greatest(p_limit,1),50)
 ), claimed as (
  update private.email_outbox e set state='sending',attempts=attempts+1,lease_until=now()+interval '2 minutes',updated_at=now()
  from picked where e.id=picked.id returning e.*
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',event_type,'recipient',recipient,'subject',subject,'body',body,'dedupe_key',dedupe_key)),'[]'::jsonb)
 into result from claimed;
 return result;
end $$;
revoke all on function public.email_claim_batch(integer) from public,anon,authenticated;
grant execute on function public.email_claim_batch(integer) to service_role;

create or replace function public.email_mark_result(p_id uuid,p_state text,p_provider text default null,p_error text default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.jwt()->>'role','') <> 'service_role' then raise exception 'Access denied'; end if;
 if p_state not in ('accepted','retry','failed') then raise exception 'Bad state'; end if;
 update private.email_outbox set
 state=case when p_state='retry' then case when attempts>=5 then 'dead' else 'pending' end else p_state end,
 next_attempt_at=case when p_state='retry' then now()+(power(2,least(attempts,5))*interval '1 minute') else next_attempt_at end,
 provider_id=coalesce(p_provider,provider_id),error_code=left(p_error,100),
 accepted_at=case when p_state='accepted' then now() else accepted_at end,
 lease_until=null,updated_at=now()
 where id=p_id and state='sending';
end $$;
revoke all on function public.email_mark_result(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.email_mark_result(uuid,text,text,text) to service_role;

create or replace function public.email_mark_delivery(p_provider text,p_event text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.jwt()->>'role','') <> 'service_role' then raise exception 'Access denied'; end if;
 if p_event not in ('delivered','bounced','failed') then raise exception 'Invalid delivery state'; end if;
 update private.email_outbox set state=p_event,delivered_at=case when p_event='delivered' then now() else delivered_at end,updated_at=now()
 where provider_id=p_provider and state in ('accepted','delivered','bounced','failed') and state<>'delivered';
end $$;
revoke all on function public.email_mark_delivery(text,text) from public,anon,authenticated;
grant execute on function public.email_mark_delivery(text,text) to service_role;

create or replace function public.admin_email_overview()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'Admin access denied'; end if;
 return jsonb_build_object('pending',(select count(*) from private.email_outbox where state='pending'),
 'accepted',(select count(*) from private.email_outbox where state='accepted'),
 'delivered',(select count(*) from private.email_outbox where state='delivered'),
 'failed',(select count(*) from private.email_outbox where state in ('failed','dead','bounced')));
end $$;
revoke all on function public.admin_email_overview() from public,anon;
grant execute on function public.admin_email_overview() to authenticated;
