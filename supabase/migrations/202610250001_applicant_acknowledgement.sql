-- Track applicant acknowledgement separately from the administrator notification.
alter table private.business_applications
  add column if not exists acknowledgement_sent_at timestamptz;

create or replace function public.claim_business_application_acknowledgement(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform private.require_user();
  select jsonb_build_object(
    'business_id',a.business_id,'business_name',b.name,
    'contact_name',a.contact_name,'contact_email',a.contact_email
  ) into result
  from private.business_applications a
  join public.businesses b on b.id=a.business_id
  where a.business_id=p_business and b.owner_id=auth.uid()
    and b.status='pending' and a.acknowledgement_sent_at is null;
  return result;
end $$;
revoke execute on function public.claim_business_application_acknowledgement(uuid) from public,anon;
grant execute on function public.claim_business_application_acknowledgement(uuid) to authenticated;

create or replace function public.complete_business_application_acknowledgement(p_business uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform private.require_user();
  update private.business_applications a
  set acknowledgement_sent_at=now()
  from public.businesses b
  where a.business_id=p_business and b.id=a.business_id
    and b.owner_id=auth.uid() and b.status='pending'
    and a.acknowledgement_sent_at is null;
end $$;
revoke execute on function public.complete_business_application_acknowledgement(uuid) from public,anon;
grant execute on function public.complete_business_application_acknowledgement(uuid) to authenticated;
