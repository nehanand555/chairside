-- Bookable professionals can publish a headshot using the existing public portfolios bucket.
-- All uploads require existing owner-scoped, MFA-protected storage policies.
alter table public.resources add column if not exists photo_path text;

create or replace function public.set_professional_photo(
  p_business uuid, p_resource uuid, p_path text default null
) returns void
language plpgsql security definer set search_path = ''
as $body$
declare expected_prefix text;
begin
  perform private.require_operator(p_business);
  if not exists (select 1 from public.resources where id=p_resource and business_id=p_business)
  then raise exception 'Professional not found'; end if;
  if p_path is not null then
    expected_prefix := p_business::text || '/professionals/' || p_resource::text || '/';
    if left(p_path,length(expected_prefix)) <> expected_prefix
       or length(p_path)>240
       or p_path !~ ('^' || expected_prefix || '[0-9]{10,20}[.](jpg|jpeg|png|webp)$')
       or not exists (
         select 1 from storage.objects
         where bucket_id='portfolios' and name=p_path
           and metadata->>'mimetype' in ('image/jpeg','image/png','image/webp')
       )
    then raise exception 'Invalid professional photo'; end if;
  end if;
  update public.resources set photo_path=p_path
  where id=p_resource and business_id=p_business;
  insert into private.audit(actor_id,action,subject_id)
  values(auth.uid(),'business_professional_photo',p_business);
end;
$body$;

revoke all on function public.set_professional_photo(uuid,uuid,text) from public;
revoke all on function public.set_professional_photo(uuid,uuid,text) from anon;
grant execute on function public.set_professional_photo(uuid,uuid,text) to authenticated;
