begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$ begin if not coalesce(ok,false) then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.must_fail(statement text,fragment text) returns void language plpgsql as $$
declare caught boolean:=false;
begin
 begin execute statement; exception when others then caught:=true; if position(fragment in sqlerrm)=0 then raise exception 'Wrong failure: % (expected %)',sqlerrm,fragment; end if; end;
 if not caught then raise exception 'Expected rejection: %',statement; end if;
end $$;
insert into auth.users(id,email,email_confirmed_at,phone,phone_confirmed_at) values
('30000000-0000-4000-8000-000000000001','spicynetwork75@gmail.com',now(),'+64211111111',now()),
('30000000-0000-4000-8000-000000000002','nehanikitanand@gmail.com',now(),'+64212222222',now()),
('30000000-0000-4000-8000-000000000003','owner@example.test',now(),'+64213333333',now());
-- Deliberately include an unintended membership: it must confer no admin rights.
insert into private.admins values('30000000-0000-4000-8000-000000000001'),('30000000-0000-4000-8000-000000000002');
insert into public.businesses(id,owner_id,name,kind,suburb,public_lat,public_lng,publish_consent)
values('30000000-0000-4000-8000-000000000010','30000000-0000-4000-8000-000000000003','Security fixture','barber','Auckland',-36.85,174.76,true);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"30000000-0000-4000-8000-000000000002","aal":"aal2","email":"spicynetwork75@gmail.com","user_metadata":{"is_admin":true,"email":"spicynetwork75@gmail.com"}}',true);
select pg_temp.check_true(not (public.account_context()->>'is_admin')::boolean,'unintended membership and forged email claims confer no admin role');
select pg_temp.must_fail('select public.admin_overview()','Admin access denied');
select pg_temp.must_fail('select public.admin_email_events()','Admin access denied');
select pg_temp.must_fail('select public.admin_health()','Admin access denied');
select pg_temp.must_fail('select public.admin_email_overview()','Admin access denied');
select pg_temp.must_fail($q$select public.admin_review('30000000-0000-4000-8000-000000000010','approved','Verified ownership evidence')$q$,'Admin access denied');
select pg_temp.must_fail($q$select public.admin_review('30000000-0000-4000-8000-000000000010','rejected','Verified ownership evidence')$q$,'Admin access denied');
select pg_temp.must_fail($q$select public.admin_review('30000000-0000-4000-8000-000000000010','suspended','Verified ownership evidence')$q$,'Admin access denied');
select pg_temp.check_true((select count(*)=0 from public.businesses),'RLS denies unintended admin access to another owner pending listing');
select pg_temp.must_fail('select * from private.admins','permission denied');
select set_config('request.jwt.claims','{"sub":"30000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select pg_temp.check_true((public.account_context()->>'is_admin')::boolean,'authorised identity can discover its admin role before MFA');
select pg_temp.must_fail('select public.admin_overview()','Admin access denied');
select pg_temp.must_fail($q$select public.admin_review('30000000-0000-4000-8000-000000000010','approved','Verified ownership evidence')$q$,'Admin access denied');
select set_config('request.jwt.claims','{"sub":"30000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select public.admin_review('30000000-0000-4000-8000-000000000010','approved','Verified ownership evidence');
select public.admin_review('30000000-0000-4000-8000-000000000010','rejected','Verified ownership evidence');
select public.admin_review('30000000-0000-4000-8000-000000000010','suspended','Verified ownership evidence');
select pg_temp.check_true((select count(*)=1 from public.businesses),'authorised admin with MFA can read reviewed listing');
reset role;
select pg_temp.check_true((select count(*)=3 from private.audit where actor_id='30000000-0000-4000-8000-000000000001' and action='admin_review'),'all authorised decisions are audited');
select pg_temp.check_true(not exists(select 1 from private.audit where actor_id='30000000-0000-4000-8000-000000000002'),'unauthorised actions leave no decision audit');
delete from private.admins where user_id='30000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.must_fail('select public.admin_overview()','Admin access denied');
reset role;
insert into private.admins values('30000000-0000-4000-8000-000000000001');
update auth.users set email_confirmed_at=null where id='30000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.must_fail('select public.admin_overview()','Admin access denied');
reset role;
update auth.users set email_confirmed_at=now() where id='30000000-0000-4000-8000-000000000001';
insert into private.blocked_users values('30000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.must_fail('select public.admin_overview()','Admin access denied');
reset role;
select pg_temp.check_true(not has_function_privilege('authenticated','private.admin_identity_allowed()','execute'),'identity helper cannot be invoked directly');
rollback;
