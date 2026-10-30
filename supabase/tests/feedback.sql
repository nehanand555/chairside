begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$ begin if not coalesce(ok,false) then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.must_fail(statement text,fragment text) returns void language plpgsql as $$
declare caught boolean:=false;
begin
  begin execute statement; exception when others then caught:=true; if position(fragment in sqlerrm)=0 then raise exception 'Wrong failure: % (expected %)',sqlerrm,fragment; end if; end;
  if not caught then raise exception 'Expected rejection: %',statement; end if;
end $$;

insert into auth.users(id,email,email_confirmed_at) values
('50000000-0000-4000-8000-000000000001','feedback@example.test',now()),
('50000000-0000-4000-8000-000000000002','spicynetwork75@gmail.com',now()),
('50000000-0000-4000-8000-000000000003','other-admin@example.test',now());
insert into auth.identities(user_id,provider) values
('50000000-0000-4000-8000-000000000001','google');
insert into private.admins(user_id) values
('50000000-0000-4000-8000-000000000002'),('50000000-0000-4000-8000-000000000003');
select pg_temp.check_true(not has_table_privilege('authenticated','private.feedback','SELECT'),'customers cannot read feedback inbox');
select pg_temp.check_true(not has_table_privilege('anon','private.feedback','INSERT'),'anonymous feedback insert denied');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"50000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select pg_temp.must_fail($q$select public.submit_feedback('short')$q$,'10–2000');
select public.submit_feedback('Thank you, I would like more search filters.');
select pg_temp.must_fail('select public.admin_feedback()','Admin access denied');
select pg_temp.must_fail($q$select public.resolve_feedback('00000000-0000-0000-0000-000000000001')$q$,'Admin access denied');
select public.submit_feedback('Second feedback message');
select public.submit_feedback('Third feedback message');
select public.submit_feedback('Fourth feedback message');
select public.submit_feedback('Fifth feedback message');
select pg_temp.must_fail($q$select public.submit_feedback('Sixth feedback message')$q$,'Please wait');
select set_config('request.jwt.claims','{"sub":"50000000-0000-4000-8000-000000000003","aal":"aal2"}',true);
select pg_temp.must_fail('select public.admin_feedback()','Admin access denied');
select set_config('request.jwt.claims','{"sub":"50000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
select pg_temp.must_fail('select public.admin_feedback()','Admin access denied');
select set_config('request.jwt.claims','{"sub":"50000000-0000-4000-8000-000000000002","aal":"aal2"}',true);
select pg_temp.check_true(jsonb_array_length(public.admin_feedback())=5,'authorised MFA admin receives feedback');
select public.resolve_feedback((public.admin_feedback()->0->>'id')::uuid);
select pg_temp.check_true(jsonb_array_length(public.admin_feedback())=4,'admin can mark feedback read');
reset role;
select pg_temp.check_true((select count(*)=5 from private.feedback),'five messages saved, resolved message retained');
rollback;
