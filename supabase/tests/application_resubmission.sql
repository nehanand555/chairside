begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$ begin if not coalesce(ok,false) then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.must_fail(statement text,fragment text) returns void language plpgsql as $$
declare caught boolean:=false;
begin
  begin execute statement; exception when others then caught:=true; if position(fragment in sqlerrm)=0 then raise exception 'Wrong failure: % (expected %)',sqlerrm,fragment; end if; end;
  if not caught then raise exception 'Expected rejection: %',statement; end if;
end $$;

insert into auth.users(id,email,email_confirmed_at) values
('40000000-0000-4000-8000-000000000001','owner@example.test',now()),
('40000000-0000-4000-8000-000000000002','other@example.test',now());
insert into auth.identities(user_id,provider) values
('40000000-0000-4000-8000-000000000001','google'),
('40000000-0000-4000-8000-000000000002','google');
insert into public.businesses(id,owner_id,name,kind,suburb,public_lat,public_lng,status,review_note,publish_consent)
values('40000000-0000-4000-8000-000000000010','40000000-0000-4000-8000-000000000001','Test studio','salon','Auckland',-36.85,174.76,'rejected','Please correct registration',true);
insert into private.business_applications(business_id,registration_number,contact_name,contact_email,contact_phone)
values('40000000-0000-4000-8000-000000000010','NZ123','Test Owner','owner@example.test','+64211234567');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"40000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
select pg_temp.check_true(public.my_pending_business_application() is null,'another user cannot read rejected application');
select pg_temp.must_fail($q$select public.update_pending_business_application('40000000-0000-4000-8000-000000000010','{}')$q$,'Only the owner');
select set_config('request.jwt.claims','{"sub":"40000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select pg_temp.check_true(public.my_pending_business_application()->>'name'='Test studio','owner can read rejected application');
select public.update_pending_business_application('40000000-0000-4000-8000-000000000010','{"name":"Updated studio","registration_number":"NZ456","contact_name":"Test Owner","contact_email":"owner@example.test","contact_phone":"+64211234567"}');
select pg_temp.check_true(public.account_context()->>'business_status'='pending','reapplication returns to pending rather than approved');
select pg_temp.must_fail($q$select public.operator_business('40000000-0000-4000-8000-000000000010')$q$,'authenticator');
reset role;
select pg_temp.check_true((select count(*)=1 from public.businesses where owner_id='40000000-0000-4000-8000-000000000001'),'resubmission does not create duplicate business');
select pg_temp.check_true((select count(*)=1 from private.email_outbox where event_type='application_updated' and business_id='40000000-0000-4000-8000-000000000010'),'review notification queued');
update public.businesses set status='suspended';
set local role authenticated;
select pg_temp.check_true(public.my_pending_business_application() is null,'suspended application cannot be edited');
select pg_temp.must_fail($q$select public.update_pending_business_application('40000000-0000-4000-8000-000000000010','{}')$q$,'Only the owner');
reset role;
update public.businesses set status='approved';
set local role authenticated;
select pg_temp.must_fail($q$select public.update_pending_business_application('40000000-0000-4000-8000-000000000010','{}')$q$,'Only the owner');
rollback;
