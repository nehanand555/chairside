-- Queue notifications for existing pending applications without recorded provider acceptance.
-- Idempotent per event type/revision/recipient; avoids sending twice on re-run.
do $$
declare a record;
begin
 for a in
  select b.id,b.name,p.contact_email,p.contact_name
  from public.businesses b join private.business_applications p on p.business_id=b.id
  where b.status='pending' and p.notification_sent_at is null
 loop
  if not exists(select 1 from private.email_outbox e where e.business_id=a.id and e.event_type in ('application_review','application_updated')) then
   perform private.enqueue_business_email(a.id,'application_review',1,'admin-routing@spicyself.invalid',
   'SpicySelf application: '||a.name,'A SpicySelf application is awaiting review: '||a.name||E'\nReference: '||a.id::text||E'\nOpen the protected Admin portal.');
  end if;
  if not exists(select 1 from private.email_outbox e where e.business_id=a.id and e.event_type='application_received') then
   perform private.enqueue_business_email(a.id,'application_received',1,a.contact_email,
   'SpicySelf application received','Your business application for '||a.name||' has been received. Reference: '||a.id::text||'.');
  end if;
 end loop;
end $$;