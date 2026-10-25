
create or replace function public.admin_email_events()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.is_admin() then raise exception 'Admin access denied'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id', e.id, 'business', b.name, 'event', e.event_type, 'state', e.state,
  'attempts',e.attempts,'error',e.error_code,'created_at',e.created_at
 ) order by e.created_at desc),'[]'::jsonb) into result
 from (select * from private.email_outbox order by created_at desc limit 50) e
 join public.businesses b on b.id=e.business_id;
 return result;
end $$;
revoke all on function public.admin_email_events() from public,anon;
grant execute on function public.admin_email_events() to authenticated;

create or replace function public.admin_retry_email(p_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare updated integer;
begin
 if not private.is_admin() then raise exception 'Admin access denied'; end if;
 -- Never blindly retry ambiguous network failures: provider may already have accepted.
 update private.email_outbox set state='pending',next_attempt_at=now(),attempts=0,
 error_code=null,lease_until=null,updated_at=now()
 where id=p_id and state in ('failed','dead') and error_code like 'http_%';
 get diagnostics updated = row_count;
 if updated>0 then
  insert into private.audit(actor_id,action,subject_id,details)
  select auth.uid(),'email_retry',business_id,jsonb_build_object('email_id',id) from private.email_outbox where id=p_id;
 end if;
 return updated>0;
end $$;
revoke all on function public.admin_retry_email(uuid) from public,anon;
grant execute on function public.admin_retry_email(uuid) to authenticated;
