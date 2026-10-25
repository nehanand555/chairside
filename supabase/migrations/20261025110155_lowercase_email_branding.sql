-- Lowercase future queued email content; preserve existing delivery history.

create or replace function private.queue_application_emails() returns trigger
language plpgsql security definer set search_path='' as $$
declare r bigint; nm text; ev text;
begin
 select name into nm from public.businesses where id=new.business_id;
 r := case when tg_op='INSERT' then 1 else coalesce((select max(revision) from private.email_outbox where business_id=new.business_id and event_type in ('application_review','application_updated')),0)+1 end;
 ev := case when tg_op='INSERT' then 'application_review' else 'application_updated' end;
 perform private.enqueue_business_email(new.business_id,ev,r,'admin-routing@spicyself.invalid','spicyself application: '||nm,
 'Business: '||nm||E'\nApplication ID: '||new.business_id::text||E'\nContact: '||new.contact_name||E'\nEmail: '||new.contact_email||E'\nRegistration: '||new.registration_number||E'\nOpen the protected Admin portal to review.');
 if tg_op='INSERT' then
   perform private.enqueue_business_email(new.business_id,'application_received',r,new.contact_email,'spicyself application received',
   'Thanks for applying to spicyself. Your application for '||nm||' is saved and awaiting review. Reference: '||new.business_id::text);
 end if;
 return new;
end $$;

create or replace function private.queue_decision_email() returns trigger
language plpgsql security definer set search_path='' as $$
declare mail text; r bigint;
begin
 if old.status is distinct from new.status and new.status in ('approved','rejected','suspended') then
   select contact_email into mail from private.business_applications where business_id=new.id;
   r := (select coalesce(max(revision),0)+1 from private.email_outbox where business_id=new.id and event_type like 'decision_%');
   perform private.enqueue_business_email(new.id,'decision_'||new.status,r,mail,'spicyself business review: '||new.status,
   'The review of '||new.name||' is now '||new.status||'.'||E'\nReview note: '||coalesce(new.review_note,'')||
   E'\nSign in to spicyself to view your application.');
 end if;
 return new;
end $$;
