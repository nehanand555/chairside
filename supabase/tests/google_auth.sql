begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$ begin if not coalesce(ok,false) then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.must_fail(statement text,fragment text) returns void language plpgsql as $$
declare caught boolean:=false;
begin
  begin execute statement; exception when others then caught:=true; if position(fragment in sqlerrm)=0 then raise exception 'Wrong failure: % (expected %)',sqlerrm,fragment; end if; end;
  if not caught then raise exception 'Expected rejection: %',statement; end if;
end $$;
-- Real Auth can store an absent phone as NULL or an empty string. Cover both.
insert into auth.users(id,phone,email,email_confirmed_at) values
('20000000-0000-4000-8000-000000000001','','owner@example.test',now()),
('20000000-0000-4000-8000-000000000002',null,'customer@example.test',now()),
('20000000-0000-4000-8000-000000000003',null,'unverified@example.test',null),
('20000000-0000-4000-8000-000000000004',null,'email-only@example.test',now()),
('20000000-0000-4000-8000-000000000005',null,'deleted@example.test',now());
insert into auth.identities(user_id,provider) values
('20000000-0000-4000-8000-000000000001','google'),
('20000000-0000-4000-8000-000000000002','google'),
('20000000-0000-4000-8000-000000000003','google'),
('20000000-0000-4000-8000-000000000004','email'),
('20000000-0000-4000-8000-000000000005','google');
update auth.users set deleted_at=now() where id='20000000-0000-4000-8000-000000000005';
insert into public.profiles(id,display_name,sms_updates) values
('20000000-0000-4000-8000-000000000001','Google owner',true),
('20000000-0000-4000-8000-000000000002','Google customer',true);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select pg_temp.check_true((public.account_context()->>'is_admin')::boolean=false,'Google identity never grants an admin role');
select pg_temp.must_fail($q$select public.apply_business('{"name":"Google home studio","kind":"home","suburb":"Auckland","lat":-36.8485,"lng":174.7633,"address":"Private Google address","publish_consent":true,"operating_declaration":true}')$q$,'authenticator');
select set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select set_config('google.shop',public.apply_business('{"name":"Google home studio","kind":"home","suburb":"Auckland","lat":-36.8485,"lng":174.7633,"address":"Private Google address","publish_consent":true,"operating_declaration":true}')::text,true);
select public.configure_business(current_setting('google.shop')::uuid,'service','{"name":"Haircut","minutes":30,"price_cents":3500}');
select public.configure_business(current_setting('google.shop')::uuid,'hours','{"hours":[{"weekday":1,"opens":"00:00","closes":"23:59"},{"weekday":2,"opens":"00:00","closes":"23:59"},{"weekday":3,"opens":"00:00","closes":"23:59"},{"weekday":4,"opens":"00:00","closes":"23:59"},{"weekday":5,"opens":"00:00","closes":"23:59"},{"weekday":6,"opens":"00:00","closes":"23:59"},{"weekday":7,"opens":"00:00","closes":"23:59"}]}');
select set_config('google.resource',(select id::text from public.resources where business_id=current_setting('google.shop')::uuid),true);
select set_config('google.service',(select id::text from public.services where business_id=current_setting('google.shop')::uuid),true);
reset role;
-- Existing private membership + aal2 is still the only way to administer listings.
insert into private.admins values('20000000-0000-4000-8000-000000000001');
set local role authenticated;
select public.admin_review(current_setting('google.shop')::uuid,'approved','Verified ownership and operating permissions');
select pg_temp.check_true(public.admin_overview()->'businesses'->0->>'owner_email'='owner@example.test','only authorised admins receive Google owner contact email');
select set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select pg_temp.must_fail('select public.admin_overview()','Admin access denied');
select pg_temp.must_fail($q$select public.operator_business(current_setting('google.shop')::uuid)$q$,'authenticator');
select set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
select pg_temp.check_true((public.account_context()->>'aal2')::boolean=false,'Google customers sign in at customer assurance');
select pg_temp.must_fail('select public.admin_overview()','Admin access denied');
select set_config('google.start',((((now() at time zone 'Pacific/Auckland')::date+1)+time '10:00') at time zone 'Pacific/Auckland')::text,true);
select set_config('google.visit',public.create_visit(current_setting('google.shop')::uuid,current_setting('google.service')::uuid,current_setting('google.resource')::uuid,'appointment',current_setting('google.start')::timestamptz)::text,true);
select pg_temp.check_true(public.visit_location(current_setting('google.visit')::uuid)->>'address'='Private Google address','confirmed Google customer can access their home-studio visit address');
select public.change_visit(current_setting('google.visit')::uuid,'cancel');
select pg_temp.must_fail($q$select public.visit_location(current_setting('google.visit')::uuid)$q$,'Address access denied');
reset role;
select pg_temp.check_true(not exists(select 1 from private.visit_contacts where visit_id=current_setting('google.visit')::uuid),'Google customer with NULL phone creates no SMS contact');
-- Empty phone is also safe even when an old SMS preference was true.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select set_config('google.empty_visit',public.create_visit(current_setting('google.shop')::uuid,current_setting('google.service')::uuid,current_setting('google.resource')::uuid,'appointment',current_setting('google.start')::timestamptz)::text,true);
select pg_temp.must_fail($q$select public.change_visit(current_setting('google.empty_visit')::uuid,'cancel')$q$,'authenticator');
select set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select public.change_visit(current_setting('google.empty_visit')::uuid,'cancel');
reset role;
select pg_temp.check_true(not exists(select 1 from private.visit_contacts where visit_id=current_setting('google.empty_visit')::uuid),'empty Auth phone does not become an invalid plus-only contact');
insert into private.blocked_users values('20000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
select pg_temp.must_fail('select public.account_context()','Please sign in');
select pg_temp.must_fail($q$select public.create_visit(current_setting('google.shop')::uuid,current_setting('google.service')::uuid,current_setting('google.resource')::uuid,'appointment',current_setting('google.start')::timestamptz)$q$,'Please sign in');
select set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000003","aal":"aal1"}',true);
select pg_temp.must_fail('select public.account_context()','Please sign in');
select set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000004","aal":"aal1","user_metadata":{"provider":"google","email_verified":true,"is_admin":true}}',true);
select pg_temp.must_fail('select public.account_context()','Please sign in');
select set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000005","aal":"aal1"}',true);
select pg_temp.must_fail('select public.account_context()','Please sign in');
select set_config('request.jwt.claims','{}',true);
select pg_temp.must_fail('select public.account_context()','Please sign in');
reset role;
select pg_temp.check_true(not has_function_privilege('authenticated','private.require_user()','execute'),'private identity guard remains inaccessible to clients');
select pg_temp.check_true(not has_function_privilege('anon','public.create_visit(uuid,uuid,uuid,text,timestamptz,jsonb)','execute'),'anonymous callers still cannot create visits');
rollback;
