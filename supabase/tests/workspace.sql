begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$ begin if not coalesce(ok,false) then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.must_fail(statement text,fragment text) returns void language plpgsql as $$
declare caught boolean:=false;
begin
  begin execute statement; exception when others then caught:=true; if position(fragment in sqlerrm)=0 then raise exception 'Wrong failure: % (expected %)',sqlerrm,fragment; end if; end;
  if not caught then raise exception 'Expected rejection: %',statement; end if;
end $$;

insert into auth.users(id,phone,phone_confirmed_at,email,email_confirmed_at) values
('60000000-0000-4000-8000-000000000001','64210000001',now(),'owner@example.test',now()),
('60000000-0000-4000-8000-000000000002','64210000002',now(),'client@example.test',now()),
('60000000-0000-4000-8000-000000000003','64210000003',now(),'stranger@example.test',now()),
('60000000-0000-4000-8000-000000000004','64210000004',now(),'spicynetwork75@gmail.com',now()),
('60000000-0000-4000-8000-000000000005','64210000005',now(),'nehanikitanand@gmail.com',now());
insert into public.profiles(id,display_name) select id,'Workspace client' from auth.users where id::text like '60000000%';
insert into private.admins values('60000000-0000-4000-8000-000000000004'),('60000000-0000-4000-8000-000000000005');
insert into public.businesses(id,owner_id,name,kind,suburb,public_lat,public_lng,status,publish_consent) values
('60000000-0000-4000-8000-000000000010','60000000-0000-4000-8000-000000000001','Workspace studio','salon','Auckland',-36.85,174.76,'approved',true),
('60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000003','Another studio','salon','Auckland',-36.85,174.76,'approved',true);
insert into public.resources(id,business_id,name) values
('60000000-0000-4000-8000-000000000020','60000000-0000-4000-8000-000000000010','Professional A'),
('60000000-0000-4000-8000-000000000021','60000000-0000-4000-8000-000000000011','Other professional');
insert into public.services(id,business_id,name,minutes,price_cents) values('60000000-0000-4000-8000-000000000030','60000000-0000-4000-8000-000000000010','Haircut',30,3500);
insert into public.hours(business_id,weekday,opens,closes) select '60000000-0000-4000-8000-000000000010',i,'00:00','23:59' from generate_series(1,7) i;
select set_config('workspace.start',((((now() at time zone 'Pacific/Auckland')::date+2)+time '10:00') at time zone 'Pacific/Auckland')::text,true);
insert into public.visits(id,business_id,resource_id,service_id,customer_id,customer_name,service_name,minutes,price_cents,kind,status,starts_at,ends_at)
values('60000000-0000-4000-8000-000000000040','60000000-0000-4000-8000-000000000010','60000000-0000-4000-8000-000000000020','60000000-0000-4000-8000-000000000030','60000000-0000-4000-8000-000000000002','Client One','Haircut',30,3500,'appointment','completed',now()-interval '2 days',now()-interval '2 days'+interval '30 minutes');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select pg_temp.must_fail($q$select public.business_clients('60000000-0000-4000-8000-000000000010')$q$,'authenticator');
select pg_temp.must_fail($q$select public.business_schedule('60000000-0000-4000-8000-000000000010',current_date)$q$,'authenticator');
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000003","aal":"aal2"}',true);
select pg_temp.must_fail($q$select public.business_clients('60000000-0000-4000-8000-000000000010')$q$,'Business access denied');
select pg_temp.must_fail($q$select public.save_client_note('60000000-0000-4000-8000-000000000010','60000000-0000-4000-8000-000000000002','Private note')$q$,'Business access denied');
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select public.configure_business('60000000-0000-4000-8000-000000000010','service','{"id":"60000000-0000-4000-8000-000000000030","name":"Haircut","minutes":30,"price_cents":3500,"category":"Cuts"}');
select pg_temp.check_true((select category='Cuts' from public.services where id='60000000-0000-4000-8000-000000000030'),'service category is persisted through existing configuration API');
select pg_temp.check_true(jsonb_array_length(public.business_clients('60000000-0000-4000-8000-000000000010')->'items')=1,'owner reads only existing clients');
select public.save_client_note('60000000-0000-4000-8000-000000000010','60000000-0000-4000-8000-000000000002','Prefers a quiet appointment');
select pg_temp.check_true(public.business_clients('60000000-0000-4000-8000-000000000010')->'items'->0->>'note'='Prefers a quiet appointment','private note persists for this business');
select pg_temp.must_fail($q$select * from private.client_notes$q$,'permission denied');
select pg_temp.must_fail($q$select public.save_client_note('60000000-0000-4000-8000-000000000010','60000000-0000-4000-8000-000000000003','Not a client')$q$,'Client not found');
select set_config('workspace.manual', public.operator_book_appointment('60000000-0000-4000-8000-000000000010','60000000-0000-4000-8000-000000000030','60000000-0000-4000-8000-000000000020',current_setting('workspace.start')::timestamptz,'Manual client')::text,true);
select public.check_in_visit(current_setting('workspace.manual')::uuid);
select public.check_in_visit(current_setting('workspace.manual')::uuid);
select pg_temp.check_true((select checked_in_at is not null from public.visits where id=current_setting('workspace.manual')::uuid),'arrival check-in is separate and idempotent');
select pg_temp.must_fail($q$select public.operator_book_appointment('60000000-0000-4000-8000-000000000010','60000000-0000-4000-8000-000000000030','60000000-0000-4000-8000-000000000020',current_setting('workspace.start')::timestamptz,'Conflicting client')$q$,'slot was just taken');
select pg_temp.check_true((public.business_overview('60000000-0000-4000-8000-000000000010',(current_setting('workspace.start')::timestamptz at time zone 'Pacific/Auckland')::date)->>'booked_value_cents')::int=3500,'booked value uses server prices, excludes cancelled and other days');
select pg_temp.check_true(jsonb_array_length(public.business_schedule('60000000-0000-4000-8000-000000000010',(current_setting('workspace.start')::timestamptz at time zone 'Pacific/Auckland')::date)->'items')=1,'schedule reads exact NZ date');
select pg_temp.must_fail($q$select public.business_schedule('60000000-0000-4000-8000-000000000010',current_date,30)$q$,'Invalid schedule');
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
select pg_temp.must_fail($q$select public.check_in_visit(current_setting('workspace.manual')::uuid)$q$,'Business access denied');
select pg_temp.must_fail($q$select public.reschedule_visit(current_setting('workspace.manual')::uuid,current_setting('workspace.start')::timestamptz+interval '3 hours')$q$,'Business access denied');
select set_config('workspace.customer', public.create_visit('60000000-0000-4000-8000-000000000010','60000000-0000-4000-8000-000000000030','60000000-0000-4000-8000-000000000020','appointment',current_setting('workspace.start')::timestamptz+interval '1 hour')::text,true);
select public.reschedule_visit(current_setting('workspace.customer')::uuid,current_setting('workspace.start')::timestamptz+interval '2 hours');
select pg_temp.must_fail($q$select public.reschedule_visit(current_setting('workspace.customer')::uuid,current_setting('workspace.start')::timestamptz)$q$,'slot was just taken');
select pg_temp.must_fail($q$select public.reschedule_visit(current_setting('workspace.customer')::uuid,current_setting('workspace.start')::timestamptz+interval '3 hours','60000000-0000-4000-8000-000000000021')$q$,'active professional');
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000005","aal":"aal2"}',true);
select pg_temp.must_fail('select public.admin_workspace_insights()','Admin access denied');
select pg_temp.must_fail('select public.admin_business_page()','Admin access denied');
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000004","aal":"aal1"}',true);
select pg_temp.must_fail('select public.admin_workspace_insights()','Admin access denied');
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000004","aal":"aal2"}',true);
select pg_temp.check_true(jsonb_array_length(public.admin_business_page('all','Workspace')->'businesses')=1,'admin search is server-side and scoped to matching records');
select pg_temp.check_true(jsonb_array_length(public.admin_business_page('all','',50)->'businesses')=0,'admin pages are bounded');
reset role;
select pg_temp.check_true((select starts_at=current_setting('workspace.start')::timestamptz+interval '2 hours' from public.visits where id=current_setting('workspace.customer')::uuid),'reschedule changes only the selected appointment');
select pg_temp.check_true((select due_at=current_setting('workspace.start')::timestamptz+interval '1 hour' from private.notification_outbox where visit_id=current_setting('workspace.customer')::uuid and kind='reminder'),'pending reminder follows rescheduled time');
insert into public.visits(business_id,resource_id,service_id,customer_name,service_name,minutes,price_cents,kind,status,starts_at,ends_at)
select '60000000-0000-4000-8000-000000000010','60000000-0000-4000-8000-000000000020','60000000-0000-4000-8000-000000000030','DST client','Haircut',30,3500,'appointment','completed',t,t+interval '30 minutes'
from (values ('2026-09-27 00:30 Pacific/Auckland'::timestamptz),('2026-09-27 23:00 Pacific/Auckland'::timestamptz)) x(t);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select pg_temp.check_true(jsonb_array_length(public.business_schedule('60000000-0000-4000-8000-000000000010','2026-09-27')->'items')=2,'NZ 23-hour daylight-saving day includes both local boundary appointments');
reset role;
update public.visits set customer_id=null where customer_id='60000000-0000-4000-8000-000000000002';
select pg_temp.check_true((select count(*)=0 from private.client_notes),'account anonymisation removes orphaned client notes');
rollback;
