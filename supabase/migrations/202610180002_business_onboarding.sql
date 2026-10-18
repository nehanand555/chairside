-- Application contact details are kept outside public business listings.
create table private.business_applications (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  registration_number text not null check(length(registration_number) between 2 and 80),
  contact_name text not null check(length(contact_name) between 2 and 120),
  contact_email text not null check(length(contact_email) between 5 and 254),
  contact_phone text not null check(length(contact_phone) between 7 and 30),
  notification_sent_at timestamptz,
  created_at timestamptz not null default now()
);
revoke all on private.business_applications from public, anon, authenticated;

-- Allow a signed-in Google customer to apply without business-level MFA.
-- MFA remains mandatory for the business dashboard and admin review.
create or replace function public.apply_business(p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  u uuid := private.require_user();
  b uuid;
  k text := p_data->>'kind';
  la double precision := (p_data->>'lat')::double precision;
  lo double precision := (p_data->>'lng')::double precision;
  reg text := trim(coalesce(p_data->>'registration_number',''));
  contact text := trim(coalesce(p_data->>'contact_name',''));
  email text := lower(trim(coalesce(p_data->>'contact_email','')));
  phone text := trim(coalesce(p_data->>'contact_phone',''));
begin
  if length(reg) not between 2 and 80 or reg !~ '^[a-zA-Z0-9][a-zA-Z0-9 /._-]*$'
    then raise exception 'Enter a valid business registration number'; end if;
  if length(contact) not between 2 and 120 then raise exception 'Enter the contact person name'; end if;
  if length(email) not between 5 and 254 or email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    then raise exception 'Enter a valid contact email'; end if;
  if length(phone) not between 7 and 30 or phone !~ '^[+0-9 ()-]+$'
    then raise exception 'Enter a valid contact phone'; end if;
  if coalesce((p_data->>'publish_consent')::boolean,false)=false then raise exception 'Consent to publish your listing is required'; end if;
  if coalesce((p_data->>'operating_declaration')::boolean,false)=false then raise exception 'Confirm your authority and operating permissions'; end if;
  insert into public.businesses(owner_id,name,kind,description,suburb,public_lat,public_lng,place_id,publish_consent)
  values(u,trim(p_data->>'name'),k,coalesce(p_data->>'description',''),trim(p_data->>'suburb'),
    case when k='home' then round(la::numeric,2)::double precision else la end,
    case when k='home' then round(lo::numeric,2)::double precision else lo end,
    nullif(p_data->>'place_id',''),true) returning id into b;
  insert into private.business_locations values(b,trim(p_data->>'address'),la,lo);
  insert into private.business_applications(business_id,registration_number,contact_name,contact_email,contact_phone)
    values(b,reg,contact,email,phone);
  insert into public.resources(business_id,name) values(b,'Chair 1');
  insert into private.audit(actor_id,action,subject_id,details)
    values(u,'business_applied',b,jsonb_build_object('operating_declaration',true,'publish_consent',true));
  return b;
end $$;

-- Keep sensitive contact information restricted to the MFA-protected admin RPC.
create or replace function public.admin_overview() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_admin() then raise exception 'Admin access denied; verify your authenticator'; end if;
  return jsonb_build_object(
    'businesses',coalesce((
      select jsonb_agg(
        to_jsonb(b)||jsonb_build_object(
          'location',to_jsonb(l),
          'owner_phone',(select nullif(phone,'') from auth.users where id=b.owner_id),
          'owner_email',(select email from auth.users where id=b.owner_id),
          'registration_number',a.registration_number,
          'contact_name',a.contact_name,
          'contact_email',a.contact_email,
          'contact_phone',a.contact_phone
        ) order by b.created_at desc
      )
      from public.businesses b
      join private.business_locations l on l.business_id=b.id
      left join private.business_applications a on a.business_id=b.id
    ),'[]'),
    'reports',coalesce((select jsonb_agg(r order by r.created_at desc) from public.reports r where status='open'),'[]')
  );
end $$;

-- The applicant can see the review status but cannot approve their own business.
create or replace function public.account_context() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid := private.require_user();
begin
  return jsonb_build_object(
    'is_admin',exists(select 1 from private.admins where user_id=u),
    'business_id',(select id from public.businesses where owner_id=u and status<>'closed'),
    'business_status',(select status from public.businesses where owner_id=u and status<>'closed'),
    'business_review_note',(select review_note from public.businesses where owner_id=u and status<>'closed'),
    'aal2',auth.jwt()->>'aal'='aal2'
  );
end $$;

-- Application approval is a verification decision. Services and hours are configured afterwards.
create or replace function public.admin_review(p_business uuid,p_status text,p_note text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.is_admin() then raise exception 'Admin access denied'; end if;
  if p_status not in ('approved','rejected','suspended') or length(p_note) not between 10 and 2000 then raise exception 'Add a review note of 10–2000 characters'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_business::text,0));
  update public.businesses set status=p_status,review_note=p_note,
    queue_open=case when p_status='approved' then queue_open else false end
  where id=p_business and status<>'closed';
  if not found then raise exception 'Business not found'; end if;
  if p_status<>'approved' then update private.payment_accounts set charges_enabled=false where business_id=p_business; end if;
  insert into private.audit(actor_id,action,subject_id,details)
    values(auth.uid(),'admin_review',p_business,jsonb_build_object('status',p_status,'note',p_note));
end $$;

-- No operational access until approval. Administrative controls remain available.
create or replace function private.require_operator(p_business uuid) returns void
language plpgsql stable security definer set search_path='' as $$
begin
  perform private.require_user();
  if not (private.owns(p_business) or private.is_admin()) then raise exception 'Business access denied'; end if;
  if coalesce(auth.jwt()->>'aal','') <> 'aal2' then raise exception 'Unlock business access with your authenticator'; end if;
  if not private.is_admin() and not exists(
    select 1 from public.businesses where id=p_business and status='approved'
  ) then raise exception 'Your business must be approved before accessing business features'; end if;
end $$;
revoke execute on function private.require_operator(uuid) from public,anon,authenticated;

-- Claim one notification per application using the applicant's authenticated session.
-- Application contact details are never returned by public discovery RPCs.
create function public.claim_business_application_notification(p_business uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  result jsonb;
begin
  perform private.require_user();
  update private.business_applications a
     set notification_sent_at = now()
    from public.businesses b
   where a.business_id=p_business and b.id=a.business_id
     and b.owner_id=auth.uid() and b.status='pending'
     and a.notification_sent_at is null
  returning jsonb_build_object(
    'business_id',a.business_id,
    'registration_number',a.registration_number,
    'contact_name',a.contact_name,
    'contact_email',a.contact_email,
    'contact_phone',a.contact_phone,
    'business_name',b.name,
    'business_kind',b.kind,
    'suburb',b.suburb
  ) into result;
  return result;
end $$;
revoke execute on function public.claim_business_application_notification(uuid) from public,anon;
grant execute on function public.claim_business_application_notification(uuid) to authenticated;
