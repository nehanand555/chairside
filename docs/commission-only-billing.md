# SpicySelf: commission-only business model (approved 2026-11-03)

## Commercial rules
- Business onboarding and all calendar, staff, service and booking management features are free. No subscription or subscription entitlement gates.
- SpicySelf charges a 6% platform commission on the final service value of **every completed booking managed in SpicySelf**, regardless of origin (customer self-booking, staff-entered, walk-in, phone).
- Cancelled, unfulfilled and no-show bookings do not accrue commission. Refunds and post-completion price corrections require reversal/adjustment entries.
- Commission basis is the final service amount excluding tips, gift-card purchase value, and any separately stated processing charges; GST treatment must be configured and confirmed before production.
- Store amounts as integer minor currency units, currency code, and rate in basis points (600). Round once per booking at settlement using a documented rounding rule. Keep immutable audit entries.
- Historical bookings must not be charged retroactively by default.

## Payment and collection
- Online payment: use Stripe Connect with connected accounts, server-side payment intents/checkout, webhook verification and idempotency; platform fee or transfer mechanics must be validated against the selected charge type.
- Cash/external EFTPOS: mark booking as paid externally and record 6% commission receivable. Do **not** claim Stripe has collected it. Add monthly invoice/settlement and reconciliation workflow, including unpaid balances and disputes.
- Never mark commission settled solely because a booking status changed. Distinguish accrued, invoiced, collected, refunded, disputed, waived.
- Prevent a business from self-marking commission as paid or modifying commission amount. Admin adjustments require reason and audit trail.

## Suggested data
- business_billing_profiles(business_id, stripe_account_id, settlement_method, billing_status, currency)
- booking_financials(booking_id UNIQUE, business_id, final_service_amount_minor, currency, commission_bps, commission_amount_minor, payment_method, completed_at, commission_state)
- commission_ledger(id, booking_id, business_id, entry_type, amount_minor, currency, external_reference, idempotency_key UNIQUE, created_at, actor_id, reason)
- settlement_batches(id, business_id, period_start, period_end, amount_minor, status, external_reference)

## Implementation order
1. Audit current migrations, booking state machine, RLS, UI and payment integrations. Do not delete subscription data until migration strategy is validated.
2. Add additive migrations, restrictive RLS and server-only commission calculation; backfill historical records as exempt.
3. On verified completion, accrue exactly one commission entry in a transaction; replays must not double-charge.
4. Add payment capture, webhook processing and external payment settlement; test refunds, partial refunds, price edits, cancellation, no-shows and concurrent completion.
5. Remove subscription pricing, checkout, paywalls and billing portal links from business UI and onboarding; replace with plain-language 6% terms.
6. Business dashboard: gross service value, 6% fees, net proceeds, unsettled balance, invoices and transactions. Admin: audit, settlement, disputes, adjustments.
7. Add integration tests and staged rollout behind a feature flag. Do not enable real charges or deploy production without explicit approval.

## Open decisions before live payments
- **Resolved:** The business absorbs the 6% commission. Customer-facing prices must not be increased by a SpicySelf commission surcharge. For a NZ$100 service, the customer pays NZ$100, SpicySelf's gross commission is NZ$6, and the business receives NZ$94 before other applicable fees and tax treatment.
- GST-inclusive versus GST-exclusive commission calculation and invoicing (NZ tax review).
- Who is merchant of record, which Stripe Connect charge type, and whether offline commission is invoiced monthly or auto-debited.
- How to handle partial refunds, deposits, tips and chargebacks.
