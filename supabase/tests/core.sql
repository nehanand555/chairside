begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$ begin if not coalesce(ok,false) then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.must_fail(statement text,fragment text) returns void language plpgsql as $$
declare caught boolean:=false;
begin
  begin execute statement; exception when others then caught:=true; if position(fragment in sqlerrm)=0 then raise exception 'Wrong failure: % (expected %)',sqlerrm,fragment; end if; end;
  if not caught then raise exception 'Expected rejection: %',statement; end if;
end $$;
insert into auth.users(id,phone,phone_confirmed_at) values
('00000000-0000-4000-8000-000000000001','+64210000001',now()),
('00000000-0000-4000-8000-000000000002','64210000002',now()),
('00000000-0000-4000-8000-000000000003','+64210000003',now()),
('00000000-0000-4000-8000-000000000004','+64210000004',now()),
('00000000-0000-4000-8000-000000000005','+64210000005',now());
insert into private.admins values('00000000-0000-4000-8000-000000000005');
insert into public.profiles(id,display_name) select id,'Customer '||right(id::text,1) from auth.users;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select pg_temp.must_fail($q$select public.apply_business('{"name":"Test shop","kind":"barber","suburb":"Auckland","lat":-36.8485,"lng":174.7633,"address":"10 Test Street","publish_consent":true,"operating_declaration":true}')$q$,'business registration number');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select set_config('test.shop',public.apply_business('{"name":"Test shop","kind":"barber","suburb":"Auckland","lat":-36.8485,"lng":174.7633,"address":"10 Test Street","publish_consent":true,"operating_declaration":true,"registration_number":"9429041234567","contact_name":"Test Owner","contact_email":"owner@example.test","contact_phone":"+64211234567"}')::text,true);
select pg_temp.must_fail($q$select public.configure_business(current_setting('test.shop')::uuid,'service','{"name":"Haircut","minutes":30,"price_cents":3500}')$q$,'approved');
select pg_temp.must_fail($q$update public.businesses set status='approved'$q$,'permission denied');
select pg_temp.must_fail($q$select public.admin_review(current_setting('test.shop')::uuid,'approved','Verified ownership')$q$,'Admin access denied');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000005","aal":"aal1"}',true);
select pg_temp.must_fail($q$select public.admin_review(current_setting('test.shop')::uuid,'approved','Verified ownership')$q$,'Admin access denied');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000005","aal":"aal2"}',true);
select public.admin_review(current_setting('test.shop')::uuid,'approved','Verified owner and operating permissions');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select public.configure_business(current_setting('test.shop')::uuid,'service','{"name":"Haircut","minutes":30,"price_cents":3500}');
select public.configure_business(current_setting('test.shop')::uuid,'hours','{"hours":[{"weekday":1,"opens":"00:00","closes":"23:59"},{"weekday":2,"opens":"00:00","closes":"23:59"},{"weekday":3,"opens":"00:00","closes":"23:59"},{"weekday":4,"opens":"00:00","closes":"23:59"},{"weekday":5,"opens":"00:00","closes":"23:59"},{"weekday":6,"opens":"00:00","closes":"23:59"},{"weekday":7,"opens":"00:00","closes":"23:59"}]}');
select set_config('test.resource',(select id::text from public.resources where business_id=current_setting('test.shop')::uuid),true);
select set_config('test.service',(select id::text from public.services where business_id=current_setting('test.shop')::uuid),true);
select set_config('test.tomorrow',((((now() at time zone 'Pacific/Auckland')::date+1)+time '10:00') at time zone 'Pacific/Auckland')::text,true);
select set_config('request.jwt.claims','{}',true);
set local role anon;
select pg_temp.check_true((select count(*)=1 from public.discover_businesses(-36.85,174.76,25)),'anonymous discovery returns approved public listings');
select pg_temp.check_true((select count(*)>0 from public.available_slots(current_setting('test.shop')::uuid,current_setting('test.service')::uuid,(now() at time zone 'Pacific/Auckland')::date+1)),'anonymous customers see real slots');
select pg_temp.check_true((select count(*)=0 from public.businesses),'private business records are not publicly selectable');
select pg_temp.must_fail('select * from private.business_locations','permission denied');
select pg_temp.must_fail('select * from private.business_applications','permission denied');
select pg_temp.must_fail('select public.integration_delete_user(gen_random_uuid())','permission denied');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
select set_config('test.visit',public.create_visit(current_setting('test.shop')::uuid,current_setting('test.service')::uuid,current_setting('test.resource')::uuid,'appointment',current_setting('test.tomorrow')::timestamptz)::text,true);
select pg_temp.must_fail($q$select public.create_visit(current_setting('test.shop')::uuid,current_setting('test.service')::uuid,current_setting('test.resource')::uuid,'appointment',current_setting('test.tomorrow')::timestamptz+interval '1 hour')$q$,'active visit');
select pg_temp.check_true((public.visit_location(current_setting('test.visit')::uuid)->>'address')='10 Test Street','confirmed customer receives visit address');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","aal":"aal1"}',true);
select pg_temp.check_true((select count(*)=0 from public.visits),'cross-customer visits hidden by RLS');
select pg_temp.must_fail($q$select public.visit_location(current_setting('test.visit')::uuid)$q$,'Address access denied');
select pg_temp.must_fail($q$select public.change_visit(current_setting('test.visit')::uuid,'cancel')$q$,'Visit access denied');
select pg_temp.must_fail($q$select public.create_visit(current_setting('test.shop')::uuid,current_setting('test.service')::uuid,current_setting('test.resource')::uuid,'appointment',current_setting('test.tomorrow')::timestamptz+interval '15 minutes')$q$,'no longer available');
select public.create_visit(current_setting('test.shop')::uuid,current_setting('test.service')::uuid,current_setting('test.resource')::uuid,'appointment',current_setting('test.tomorrow')::timestamptz+interval '30 minutes');
select pg_temp.check_true((select count(*)=1 from public.visits),'adjacent appointment is permitted');
select public.change_visit((select id from public.visits limit 1),'cancel');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
select public.change_visit(current_setting('test.visit')::uuid,'cancel');
select pg_temp.must_fail($q$select public.visit_location(current_setting('test.visit')::uuid)$q$,'Address access denied');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","aal":"aal2"}',true);
select set_config('test.home',public.apply_business('{"name":"Private home studio","kind":"home","suburb":"Auckland","lat":-36.848512,"lng":174.763312,"address":"Secret entrance 15","publish_consent":true,"operating_declaration":true,"registration_number":"9429041234567","contact_name":"Test Owner","contact_email":"owner@example.test","contact_phone":"+64211234567"}')::text,true);
select pg_temp.must_fail($q$select public.configure_business(current_setting('test.home')::uuid,'queue','{"open":true}')$q$,'approved');
select pg_temp.must_fail($q$select public.operator_business(current_setting('test.shop')::uuid)$q$,'Business access denied');
reset role;
select pg_temp.check_true((select public_lat=-36.85 and public_lng=174.76 from public.businesses where id=current_setting('test.home')::uuid),'home public coordinates are approximate');
select pg_temp.check_true((select lat=-36.848512 from private.business_locations where business_id=current_setting('test.home')::uuid),'exact coordinates exist only in private location storage');
select pg_temp.check_true((select phone='+64210000002' from private.visit_contacts where visit_id=current_setting('test.visit')::uuid),'Auth phone storage is converted to SMS E.164 format');
select pg_temp.check_true(not has_function_privilege('authenticated','public.integration_paid(text,uuid,text,integer,text)','execute'),'customers cannot mark payments paid');
select pg_temp.check_true(not has_table_privilege('authenticated','private.admins','insert'),'users cannot self-grant admin');
-- Queue flow is tested in today's session; at midnight boundary test closure rejection instead.
do $$
declare q1 uuid;q2 uuid;rid uuid:=current_setting('test.resource')::uuid;sid uuid:=current_setting('test.service')::uuid;bid uuid:=current_setting('test.shop')::uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
  perform public.configure_business(bid,'queue','{"open":true}');
  if (now() at time zone 'Pacific/Auckland')::time>time '22:50' then
    update public.services set minutes=240 where id=sid;
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
    perform pg_temp.must_fail(format('select public.create_visit(%L,%L,%L,''queue'')',bid,sid,rid),'No more queue capacity');
  else
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
    q1:=public.create_visit(bid,sid,rid,'queue');
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","aal":"aal1"}',true);
    q2:=public.create_visit(bid,sid,rid,'queue');
    perform pg_temp.check_true((public.queue_estimates(bid,sid)->0->>'waiting')::integer=2,'public queue estimate includes the people waiting');
    perform pg_temp.check_true(position('customer_id' in public.queue_estimates(bid,sid)::text)=0 and position('customer_name' in public.queue_estimates(bid,sid)::text)=0,'public queue estimates contain no customer identifiers');
    perform pg_temp.check_true((select a.starts_at<b.starts_at from public.visits a,public.visits b where a.id=q1 and b.id=q2),'queue estimates follow insertion order');
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
    perform pg_temp.must_fail(format('select public.change_visit(%L,''start'')',q2),'first person');
    perform public.change_visit(q1,'start');
    perform pg_temp.must_fail(format('select public.change_visit(%L,''start'')',q2),'Finish the current');
    perform public.change_visit(q1,'complete');
    perform public.change_visit(q2,'start');
    perform pg_temp.must_fail(format('select public.change_visit(%L,''cancel'')',q2),'upcoming visits');
    perform public.change_visit(q2,'complete');
    perform public.configure_business(bid,'queue','{"open":false}');
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
    perform pg_temp.must_fail(format('select public.create_visit(%L,%L,%L,''queue'')',bid,sid,rid),'paused');
    perform pg_temp.check_true((select count(*)=2 from public.visits where id in(q1,q2) and status='completed'),'queue visits complete without removing history');
  end if;
end $$;
rollback;
