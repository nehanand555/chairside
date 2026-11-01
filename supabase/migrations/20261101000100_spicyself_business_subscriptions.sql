-- Subscriptions are reconciled only through server-side verified Stripe events.
create table if not exists public.business_subscriptions (
  business_id uuid primary key references public.businesses(id) on delete restrict,
  stripe_customer_id text unique,
  stripe_subscription_id text unique,
  stripe_checkout_session_id text,
  status text not null default 'not_subscribed',
  price_id text,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint valid_subscription_status check (status in ('not_subscribed','checkout_pending','incomplete','incomplete_expired','trialing','active','past_due','canceled','unpaid','paused'))
);
alter table public.business_subscriptions enable row level security;
revoke all on public.business_subscriptions from anon, authenticated, public;
grant select, insert, update, delete on public.business_subscriptions to service_role;
comment on table public.business_subscriptions is 'Stripe-verified membership state; never trust client-reported billing status. Membership enforcement is a separate release gate.';
