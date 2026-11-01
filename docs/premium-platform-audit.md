# spicyself platform audit and implementation

Baseline: `83ca606` (2026-11-01). Work is isolated on `improve/premium-workspaces`.
Production database, users, Stripe configuration and launch flags must not change
without explicit approval. All findings distinguish source from live state.

## Architecture and gaps before implementation

| Area | Existing implementation | Gap / constraint |
| --- | --- | --- |
| Flutter | Shared theme and reusable forms/cards; five customer destinations; separate merchant route | Large screens mix operations, setup and billing; inconsistent density and error/loading presentation |
| Discovery | Google Places Edge Function plus verified spicyself listings; categories, location and map | Do not invent availability for public listings; keep external booking links separate |
| Booking | Real available_slots/create_visit RPCs; NZ timezone; advisory locking and GiST exclusion constraint | Needs clearer step hierarchy; rescheduling and client notes need explicit server support |
| Merchant | Queue controls, daily visits, history, editable services/chairs/hours/photos, billing tab | Date picker is not a day/week schedule; no dedicated client workspace; summary counts use loaded visits |
| Admin | Protected business review, audit writes, reports, feedback and notification retry | Combined page has little information hierarchy, search or pagination; billing/security need dedicated sections |
| Subscriptions | Price ID, gated checkout, signature verification and authoritative subscription retrieval | Price livemode not checked; renewal timestamp assumes legacy Stripe field; invoice reconciliation lacks tests; no enforcement rollout/grace plan |
| Appointment payments | Standard Connect onboarding; direct-charge migration planned | Checkout deliberately blocked. Legacy destination/refund code must not be re-enabled. No verified live charge/refund path |
| Delivery | GitHub checks and Cloudflare Pages; Edge Functions deployed independently | Migration versions drift between local and live; several security/branding migrations are missing live. A successful web deploy does not prove backend parity |

## Live read-only security evidence

On 2026-11-01, `private.is_admin()` checks private membership and AAL2, but not
the explicit verified-email allowlist. `account_context()` exposes the membership
flag. The local `20261025105955_restrict_admin_identity.sql` already addresses
this; it is absent from live migration history. Do not blindly bulk-apply older
migrations because deployed versions and local filenames differ.

For the two accounts named in the request, the reported unintended account has
no current private.admins membership and zero audit rows for `admin_review`.
The authorised account has membership and five review audit rows. This does not
prove the historical report was impossible, nor identify a historical session
mix-up. Existing callback tests cover stale-session isolation. No live account
was impersonated to approve or reject a real business.

All exposed public application tables inspected have RLS enabled. Private tables
are mostly protected by revoked grants and security-definer RPCs rather than RLS.
New private tables must also enable RLS. Each privileged RPC must check identity,
ownership and AAL2; admin identity must come from verified Auth-owned fields.

## Release boundaries

- No production deployment, real charges, subscription enforcement, destructive
  data migration or replacement of working integrations is authorised here.
- Live Stripe price metadata and delivery cannot be claimed verified without
  authenticated Stripe read access. Preserve feature flags until that evidence
  and connected-account payment/refund tests exist.
- Client notes must be business-scoped, limited to existing clients, and available
  only through protected owner/admin RPCs. Public listings must never gain access.
- Calendar and metrics must label partial data honestly; use NZ dates including DST.
- No manufactured reviews, revenue, availability, staff duty or billing status.

Implementation commits and final verification results are recorded below as work
is completed.
