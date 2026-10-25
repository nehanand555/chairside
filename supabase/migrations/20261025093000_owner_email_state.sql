
create or replace function public.my_application_email_state(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s text;
begin
 perform private.require_user();
 if not exists(select 1 from public.businesses where id=p_business and owner_id=auth.uid()) then raise exception 'Not your application'; end if;
 select state into s from private.email_outbox where business_id=p_business
 and event_type in ('application_review','application_updated')
 order by created_at desc limit 1;
 return jsonb_build_object('state',coalesce(s,'missing'));
end $$;
revoke all on function public.my_application_email_state(uuid) from public,anon;
grant execute on function public.my_application_email_state(uuid) to authenticated;
