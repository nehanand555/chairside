# spicyself — Stripe Connect real payments launch checklist

**Launch state: NOT READY FOR LIVE CHARGES.** Do not enable real payment checkout before every item is completed and evidenced.

## Commercial model selected
- Stripe handles processing pricing and bills connected businesses directly.
- Use Stripe-connected accounts with Stripe-managed fee liability and **direct charges** in the connected-account context.
- The current deployed legacy implementation creates Express accounts and **destination charges** on the platform. It does not meet the chosen model.
- Current implementation has a safety guard that refuses live checkout with sk_live keys; do not remove it until the direct-charge migration is verified.

## Platform setup
- [ ] Activate the platform Stripe account in New Zealand and verify its legal/business and payout details.
- [ ] Configure Stripe Connect for Stripe-managed pricing, check accounts' controller.fees.payer, dashboard, risk and liability settings with Stripe.
- [ ] Use a restricted server-side production key if supported for required APIs. Store only in Supabase Edge Function secrets (STRIPE_SECRET_KEY); never GitHub, Flutter, logs or chat.
- [ ] Set trusted APP_URL=https://www.spicyself.com, never client-supplied redirect URLs.
- [ ] Register platform and Connect webhook endpoints in the correct live Stripe environment; store webhook signing secrets in Supabase.
- [ ] Ensure all required Stripe webhook event types are subscribed and signatures are verified.
- [ ] Confirm billing/processing fees, refunds, dispute handling, business terms and responsibility disclosures.

## Engineering prerequisites
- [ ] Switch payment flow from destination charges to direct charges created **on the connected account**.
- [ ] Ensure connected businesses self-onboard and complete Stripe identity verification and can receive payouts; block until both charges_enabled and payouts_enabled.
- [ ] Reconcile backend checkout session identifiers with connected-account webhook events and validate event.account against stored business Stripe account ID.
- [ ] Change refunds to run in correct connected-account context; do not use reverse_transfer on direct charges.
- [ ] Validate duplicate, delayed, failed and out-of-order webhook/refund events with idempotency.
- [ ] Confirm no payment can be charged for another business, cancelled appointment or stale checkout.
- [ ] Add concurrency-safe E2E tests for checkout, processing fees, payout, refund, dispute and chargeback events.
- [ ] Enforce server-side admin authorization and MFA, and audit reported account-switching issue before production money flows.

## Production rollout
- [ ] Complete tests in Stripe sandbox with at least two independently verified connected businesses.
- [ ] Inspect Supabase payment/refund tables, key restrictions and Edge Function logs.
- [ ] Have an operator complete a tiny real payment and refund end to end; verify the amount, fee payer and payee in Stripe before broad rollout.
- [ ] Only after the above, remove the live-checkout safety guard in a separately reviewed change.

Stripe references:
- https://stripe.com/nz/connect/pricing
- https://docs.stripe.com/connect/direct-charges
- https://docs.stripe.com/connect/webhooks

## Settings to enter in the live Stripe Dashboard

1. Open https://dashboard.stripe.com/settings/account and complete the platform's legal entity, New Zealand address, representative, public support contact, bank and tax details. Confirm the account is activated for live payments.
2. Open https://dashboard.stripe.com/settings/connect and select a **Stripe-owned pricing / Stripe-billed merchant** commercial model (not platform-billed). If the dashboard does not offer this, ask Stripe support before onboarding merchants. Confirm fee and loss responsibility for your account configuration.
3. Set Connect branding to lowercase **spicyself** and the verified website `https://www.spicyself.com`. Keep the support contact accurate.
4. Open https://dashboard.stripe.com/apikeys in **live mode**. Copy the live secret key into Supabase Edge Function Secrets, key `STRIPE_SECRET_KEY`. Never copy it to Flutter, GitHub, or a chat.
5. Open https://dashboard.stripe.com/workbench/webhooks in **live mode**. Add two event destinations at the same HTTPS endpoint:
   `https://nylhyzveicmgqmckveyr.supabase.co/functions/v1/stripe-webhook`
   - Destination A: **Your account** events. Start with `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `refund.created`, `refund.updated`.
   - Destination B: **Connected accounts** events. Start with `account.updated`, `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `refund.created`, `refund.updated`, `account.application.deauthorized`, `charge.dispute.created`, `payout.failed`.
   - Each destination has its **own** signing secret that starts with `whsec_`. Put destination A's in Supabase as `STRIPE_WEBHOOK_SECRET`, and destination B's as `STRIPE_CONNECT_WEBHOOK_SECRET`.
   - Event delivery configuration is **not** proof that the current handler supports each event type; disputes, direct-charge fulfilment and direct-charge refunds must be implemented and tested before go-live.
6. In Supabase https://supabase.com/dashboard/project/nylhyzveicmgqmckveyr/settings/functions, set `APP_URL=https://www.spicyself.com`. The code also has this public canonical fallback, but setting it explicitly makes the deployment easier to audit.
7. Leave `ENABLE_AFTERPAY` unset/false unless separately activated and tested. Do not configure live payments or bypass the checkout safety gate merely because a key is saved.

**Important:** No Stripe account API keys or webhook signing secrets can be inspected or changed using the connected Supabase tools in this conversation. Stripe dashboard settings and the two signing secrets require authenticated access to your Stripe account.

## Readiness criteria for switching on actual charges
- [ ] Stripe shows live platform activation and Connect Stripe-owned pricing.
- [ ] Both webhook destinations deliver events with valid signatures.
- [ ] Direct checkout runs with the `Stripe-Account` context, **not** `transfer_data.destination`.
- [ ] Connected events are matched to the correct business account and stored checkout session.
- [ ] Refunds use connected-account context and do not use legacy `reverse_transfer`.
- [ ] No unresolved admin-account privilege leak.
- [ ] Both test and live small-payment plus refund scenarios have been verified.
- [ ] Only then remove the protective checkout gate, with reviewed release.
