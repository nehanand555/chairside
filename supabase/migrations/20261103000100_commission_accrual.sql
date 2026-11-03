-- Commission accrual only. This migration does NOT collect money or change Stripe configuration.
-- Existing completed visits are intentionally exempt from retrospective charging.
create table if not exists private.booking_commissions (
  visit_id uuid primary key references public.visits(id) on delete restrict,
  business_id uuid not null references public.businesses(id) on delete restrict,
  service_amount_cents integer not null check (service_amount_cents >= 0),
  commission_bps integer not null default 600 check (commission_bps = 600),
  commission_cents integer not null check (commission_cents >= 0),
  currency text not null default 'NZD' check (currency = 'NZD'),
  collection_state text not null default 'uncollected'
    check (collection_state in ('uncollected','invoiced','collected','waived','disputed')),
  accrued_at timestamptz not null default now(),
  constraint commission_not_above_service check (commission_cents <= service_amount_cents)
);
create index if not exists booking_commissions_business_accrued
  on private.booking_commissions(business_id, accrued_at desc);
alter table private.booking_commissions enable row level security;
revoke all on private.booking_commissions from public, anon, authenticated;
grant select, insert, update, delete on private.booking_commissions to service_role;

create or replace function private.accrue_visit_commission() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    if new.price_cents < 0 then raise exception 'Invalid service amount'; end if;
    insert into private.booking_commissions
      (visit_id,business_id,service_amount_cents,commission_cents)
    values (new.id,new.business_id,new.price_cents,
      ((new.price_cents::bigint * 600 + 5000) / 10000)::integer)
    on conflict (visit_id) do nothing;
  end if;
  return new;
end $$;
revoke all on function private.accrue_visit_commission() from public, anon, authenticated;
drop trigger if exists accrue_visit_commission on public.visits;
create trigger accrue_visit_commission
after update of status on public.visits for each row
execute function private.accrue_visit_commission();

-- Read-only operator report. Never exposes another business's financials.
create or replace function public.business_commission_summary(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  perform private.require_operator(p_business);
  select jsonb_build_object(
    'currency','NZD',
    'commission_bps',600,
    'completed_service_cents',coalesce(sum(service_amount_cents),0),
    'commission_accrued_cents',coalesce(sum(commission_cents),0),
    'commission_uncollected_cents',coalesce(sum(commission_cents)
      filter (where collection_state in ('uncollected','invoiced','disputed')),0),
    'commission_collected_cents',coalesce(sum(commission_cents)
      filter (where collection_state = 'collected'),0),
    'bookings',count(*)
  ) into result
  from private.booking_commissions where business_id=p_business;
  return result;
end $$;
revoke all on function public.business_commission_summary(uuid) from public, anon;
grant execute on function public.business_commission_summary(uuid) to authenticated;
comment on function public.business_commission_summary(uuid) is
  'Accrual reporting only. Uncollected does not mean charged; payment settlement is a separate integration.';
notify pgrst, 'reload schema';
