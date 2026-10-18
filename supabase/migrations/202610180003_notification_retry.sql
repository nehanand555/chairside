-- Older notification attempts were acknowledged before delivery. Re-enable
-- manual retry for existing pending applications. This does NOT send any emails.
update private.business_applications a
   set notification_sent_at = null
  from public.businesses b
 where a.business_id = b.id and b.status = 'pending'
   and a.notification_sent_at is not null;

-- Do not acknowledge an email until the provider has accepted it.
-- The previous claim function acknowledged before Resend was called, preventing retries.
create or replace function public.claim_business_application_notification(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform private.require_user();
  select jsonb_build_object(
    'business_id',a.business_id,
    'registration_number',a.registration_number,
    'contact_name',a.contact_name,
    'contact_email',a.contact_email,
    'contact_phone',a.contact_phone,
    'business_name',b.name,
    'business_kind',b.kind,
    'suburb',b.suburb
  ) into result
  from private.business_applications a
  join public.businesses b on b.id=a.business_id
  where a.business_id=p_business and b.owner_id=auth.uid()
    and b.status='pending' and a.notification_sent_at is null;
  return result;
end $$;

create function public.complete_business_application_notification(p_business uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform private.require_user();
  update private.business_applications a set notification_sent_at=now()
  from public.businesses b
  where a.business_id=p_business and b.id=a.business_id
    and b.owner_id=auth.uid() and b.status='pending'
    and a.notification_sent_at is null;
end $$;
revoke execute on function public.complete_business_application_notification(uuid) from public,anon;
grant execute on function public.complete_business_application_notification(uuid) to authenticated;
