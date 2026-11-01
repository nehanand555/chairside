# spicyself Business — NZ$49.99 per month

## Model
- Approved spicyself business accounts may subscribe for NZ$49.99/month.
- Stripe-hosted Billing Checkout charges the **spicyself platform** subscription, separately from barber/salon customer payments.
- Non-member Google listings and their external website links remain **free**.
- Business membership does not currently gate operator features: **enforcement is a future reviewed launch step**, so existing approved businesses are not accidentally locked out.
- Live subscription checkout is **OFF by default**, controlled by Edge Function secret `ENABLE_BUSINESS_SUBSCRIPTION_CHECKOUT=true` after launch verification.
- The server validates the Stripe price rather than trusting a client amount.

## Price configuration
- Stripe product: spicyself Business Plan
- Stripe price ID: `price_1UWtMV00BuF4kp6TV3uWObsP`
- Exact price expected by the backend: NZD 4999 cents, recurring monthly, quantity 1.
- Confirm this is an **active, live-mode** price in the correct Stripe account (not the earlier $0 price).
- Stripe restricted server API key needs access for Customers create, Prices read, Checkout Sessions create/retrieve/expire, Subscriptions retrieve, and Billing Portal Sessions create.

## Stripe platform webhook (not the connected-account webhook)
Update **spicyself-platform-webhook** at https://dashboard.stripe.com/workbench/webhooks and add:
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `checkout.session.completed` (already selected)
- Optionally select `invoice.paid` and `invoice.payment_failed` for delivery monitoring; **the current handler does not process invoice events** and access is reconciled using subscription lifecycle events.

Do not add subscription events only to the connected-account destination: this product is billed by the platform itself.

## Secure backend setup
- New Supabase function: `business-subscription` with `verify_jwt=false`, because it validates the Bearer JWT with `authenticated()` and verifies business ownership/admin and MFA in PostgreSQL via `operator_business`.
- Action `status` returns membership state and feature gate; `checkout` creates a Stripe-hosted subscription session; `portal` opens Stripe's self-service billing page.
- Subscription data stored in `public.business_subscriptions` with RLS and all anon/authenticated privileges revoked. Only the service role writes it after signature-verified events.
- The `stripe-webhook` Edge Function verifies `STRIPE_WEBHOOK_SECRET` for platform events and `STRIPE_CONNECT_WEBHOOK_SECRET` for connected events, then matches platform subscription event customer ID, business ID, and the registered checkout session. It retrieves current Stripe subscription status to handle event reordering.
- Save live values securely in Supabase Edge Function Secrets: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_CONNECT_WEBHOOK_SECRET`, and `APP_URL=https://www.spicyself.com`. Never commit secrets.
- For live readiness, configure the Stripe Billing Portal to allow customers to update payment methods and cancel their subscription. Verify policies and handling of failed payments.
- Do **not** enable `ENABLE_BUSINESS_SUBSCRIPTION_CHECKOUT` until verified.

## Test and go-live checklist
- [ ] Verify the Price ID belongs to the right live-mode Stripe account and is NZ$49.99 recurring monthly.
- [ ] Check live Stripe Connect account creation separately from subscription billing.
- [ ] Confirm platform webhook receives and verifies subscription lifecycle events.
- [ ] Exercise sandbox Stripe Checkout + webhook for new membership; repeat event delivery and confirm no duplicate rows.
- [ ] Exercise sandbox payment failure, cancellation, renewal, duplicate checkout, and billing portal updates; confirm Supabase state matches Stripe.
- [ ] Verify Flutter formatting/analyzer/widget tests and staging web deployment.
- [ ] Audit admin authorization and account-switching before accepting live customer financial transactions.
- [ ] Enable checkout explicitly; first use a controlled small-scope live subscription and verify receipt, status, cancellation and refund policy.
- [ ] Only then introduce backend **membership-based operator access enforcement** with a grace period and migration policy for approved businesses.

## Known limitations
- The current feature flag blocks checkout (no membership can be charged until deliberately enabled).
- Membership is informational in the dashboard; it does not yet restrict tools.
- Subscription invoice events are not yet reconciled individually; canonical status is updated on `customer.subscription.*`.
- Stripe business payments using Connect direct charges remain separately disabled pending reconciliation/refunds testing.
- Supabase functions being ACTIVE does **not** prove Stripe webhooks work. Verify deliveries in the Stripe Dashboard.
