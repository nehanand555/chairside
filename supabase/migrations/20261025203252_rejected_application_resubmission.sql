-- Owners may correct pending or rejected applications and submit for review.
-- Admin approval remains a separate, privileged action.
create or replace function public.my_pending_business_application()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform private.require_user();
  select jsonb_build_object(
    'business_id',b.id,'name',b.name,'kind',b.kind,
    'description',b.description,'suburb',b.suburb,
    'registration_number',a.registration_number,
    'contact_name',a.contact_name,'contact_email',a.contact_email,
    'contact_phone',a.contact_phone,
    'notification_sent_at',a.notification_sent_at
  ) into result
  from public.businesses b
  join private.business_applications a on a.business_id=b.id
  where b.owner_id=auth.uid() and b.status in ('pending','rejected')
  order by b.created_at desc limit 1;
  return result;
end $$;
revoke execute on function public.my_pending_business_application() from public,anon;
grant execute on function public.my_pending_business_application() to authenticated;

create or replace function public.update_pending_business_application(p_business uuid,p_data jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare
  u uuid := private.require_user();
  n text := trim(coalesce(p_data->>'name',''));
  d text := trim(coalesce(p_data->>'description',''));
  reg text := trim(coalesce(p_data->>'registration_number',''));
  contact text := trim(coalesce(p_data->>'contact_name',''));
  email text := lower(trim(coalesce(p_data->>'contact_email','')));
  phone text := trim(coalesce(p_data->>'contact_phone',''));
begin
  perform pg_advisory_xact_lock(hashtextextended(p_business::text,0));
  if not exists(select 1 from public.businesses where id=p_business and owner_id=u and status in ('pending','rejected'))
    then raise exception 'Only the owner of a pending or rejected application can update it'; end if;
  if length(n) not between 2 and 160 then raise exception 'Enter a business name of 2–160 characters'; end if;
  if length(d)>2000 then raise exception 'Description is too long'; end if;
  if length(reg) not between 2 and 80 or reg !~ '^[a-zA-Z0-9][a-zA-Z0-9 /._-]*$'
    then raise exception 'Enter a valid registration number'; end if;
  if length(contact) not between 2 and 120 then raise exception 'Enter the contact person name'; end if;
  if length(email) not between 5 and 254 or email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    then raise exception 'Enter a valid contact email'; end if;
  if length(phone) not between 7 and 30 or phone !~ '^[+0-9 ()-]+$'
    then raise exception 'Enter a valid contact phone'; end if;
  update public.businesses set name=n,description=d,status='pending',review_note='',queue_open=false where id=p_business;
  update private.business_applications
  set registration_number=reg,contact_name=contact,contact_email=email,
      contact_phone=phone,notification_sent_at=null
  where business_id=p_business;
  insert into private.audit(actor_id,action,subject_id,details)
  values(u,'business_application_updated',p_business,jsonb_build_object('resubmitted',true));
end $$;
revoke execute on function public.update_pending_business_application(uuid,jsonb) from public,anon;
grant execute on function public.update_pending_business_application(uuid,jsonb) to authenticated;
