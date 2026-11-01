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

## Implemented changes and verification

All results below are local unless explicitly marked live. The baseline checkout
and its existing uncommitted changes were preserved. Working checkout:
`/tmp/spicy-premium-workspaces`, branch `improve/premium-workspaces`.

| Area | Result | Evidence / limits |
| --- | --- | --- |
| Design system and navigation | PASS locally | Original forest/cream theme, clearer hierarchy, responsive workspace navigation, adaptive records, skeletons, stale-panel reset. Widget tests cover 360/768/1440 widths and enlarged text. No production visual sign-off yet. |
| Discovery and public listings | PASS regression suite | Existing real Google Places/listing/map integration retained; no manufactured reviews or availability. Live Maps/browser journey not reverified in this task. |
| Customer appointments | PASS locally | Service/time/review hierarchy, Any available or specific professional, real slot filtering, customer-owned reschedule. Backend retains server prices, availability, business approval and conflicts. |
| Merchant operations | PASS locally | Exact NZ-day server summary, day/week schedule and pagination, manual booking, reschedule, check-in, existing queue/start/complete/no-show controls, service categories. Booked value is explicitly not settled revenue; resources are not labelled staff on duty. |
| Clients | PASS locally | Business-scoped search, bounded history, private notes and repeat booking. Notes require an existing relationship and protected RPC; removal of the last customer relationship removes orphan notes. |
| Admin workspace | PASS locally | Separate overview/applications/businesses/memberships/notifications/support/security; server search and pagination; bounded audit/subscription lists; existing review confirmations retained. |
| Explicit admin identity and MFA | PASS locally; FAIL live parity | SQL tests deny the unintended account even when given an admin-table row and AAL2. Authorised admin without AAL2 is denied. Live allowlist migration is missing, as described above. Historical cause remains NOT VERIFIED. |
| Session isolation and existing flows | PASS regression suite | Existing callback, role loss, application resubmission, feedback and deletion regressions pass. Two-account live browser testing remains NOT VERIFIED. |
| Billing reconciliation | PASS locally | Exact price/livemode checks, item-level subscription periods, authoritative invoice-event reconciliation, wrong-price/customer/replaced-subscription rejection. 25 Deno tests pass. |
| Live membership price and Connect payments | NOT VERIFIED | Authenticated Stripe evidence unavailable. Checkout flags and legacy checkout blocks remain intact; no real charges, new Connect accounts, refunds or enforcement enabled. |
| Database deployment | NOT DEPLOYED | New migration is local; existing live/local migration drift requires an explicit reconciliation plan before release. |
| Web deployment | NOT DEPLOYED | Public `https://www.spicyself.com/version.json` read on 2026-11-01 returns `83ca606032a77af9d2d41859df10fa2adc6013c9`; it does not contain this branch. |
| CI for this branch | NOT VERIFIED | Branch was not pushed and no new Actions run was triggered. Last inspected main checks/deploy for baseline `83ca606` succeeded; this does not certify these commits. |

### Validation performed

- `flutter pub get --enforce-lockfile`: PASS; `pubspec.lock` unchanged.
- `dart format --language-version=3.13 --output=none --set-exit-if-changed lib test`:
  PASS, 31 files, no changes. The language override matches the CI toolchain.
- `flutter analyze`: PASS, no issues.
- `flutter test`: PASS, **93 tests** including nine new workspace regressions.
- `deno check supabase/functions/*/index.ts`: PASS.
- `deno test --allow-env=SPICYSELF_ADMIN_URL,ALLOWED_ORIGINS supabase/functions/_shared/*_test.ts`:
  PASS, **25 tests**.
- Tooling: **14 Python tests**, **5 Node tests** pass.
- Fresh local database: all migrations apply and **eight SQL suites** pass
  (core, integrations, Google auth, admin security, email outbox, application
  resubmission, feedback, workspace). Local PostgreSQL 18.4; CI uses 17, so the
  exact CI database version has not been rerun here.
- **Four real database race cases** pass: customer/customer same slot, one
  customer/two businesses, manual/manual same slot, reschedule/reschedule same
  slot. Each conflict leaves exactly one reservation. Local psql-compatible test
  adapter used Node pg connections; CI uses psql directly.
- `python3 tool/bootstrap.py` and `flutter build web --release --dart-define-from-file=build-config.json`:
  PASS in isolated checkout with no production credentials. Build output is
  `build-local/web` because this checkout inherits the local Flutter build-dir
  setting. Flutter emits optional Wasm compatibility and missing unused Cupertino
  font-family warnings; the JavaScript release build succeeds.
- `git diff --check`: PASS. Changed committed blobs checked for private-key,
  Stripe-secret, Google Maps-key, GitHub-token and Supabase-secret patterns:
  none found. Local configs and `.p8` files are excluded from these commits.
  Pattern checks are not a substitute for revoking credentials exposed elsewhere.

### Source changes

- Shared: `lib/screens/common.dart`, `workspace.dart`, `lib/data/store.dart`.
- Customer: `booking.dart`, `visits.dart`.
- Merchant: `business.dart`, new `scheduling.dart`, new `clients.dart`.
- Admin: `admin.dart` plus updated role/navigation fixtures.
- Backend: `20261101093919_premium_workspace_operations.sql`; private note table
  with RLS and revoked direct grants, guarded RPCs, bounded queries, targeted
  indexes and existing transaction/advisory-lock/exclusion protections. Existing
  `configure_business` behavior retained while adding service category support.
- Billing: shared membership policy and authoritative reconciliation, checkout
  validation and regression tests. No appointment checkout enablement.
- CI: includes the new SQL workspace suite; concurrency suite now also covers
  operator bookings and reschedules.

### Local commits

1. `8d1ff22` — design foundation and gap assessment.
2. `351272b` — asynchronous panel isolation and adaptive records.
3. `a273009` — protected backend operations and SQL/concurrency regressions.
4. `0703d33` — merchant calendar/clients and customer appointment improvements.
5. `4d7af14` — admin sections and responsive/role-based UI regressions.
6. `93b9554` — membership pricing and authoritative Stripe event tests.

### Remaining release work

1. Reconcile deployed migration versions, then explicitly approve and apply the
   missing verified-admin restriction and new workspace migration. The new UI
   depends on the new RPCs; deploying the web alone will cause unavailable-service
   errors. Confirm grants/RLS and repeat rejection tests against staging first.
2. Push the reviewed branch through PR checks against PostgreSQL 17 and review
   the mobile/desktop screens with real staging data. No push or deployment was
   performed by this task.
3. Verify the supplied price through authenticated Stripe read access. Test the
   Standard Connect direct-charge, webhook, refund and reconciliation paths in
   test mode before seeking separate live-checkout approval. Keep launch flags
   off and subscription access enforcement inactive until then.
4. Test account switching, MFA enrolment, live Google Maps, email delivery and
   owner/admin workflows with consented staging accounts; unit/widget tests do
   not prove those external environments work.
5. Rescheduling moves unsent reminders safely, but this change does not introduce
   a separate appointment-change email template. Existing confirmations,
   cancellations, reminders and retry infrastructure remain. Client history only
   includes linked spicyself clients; external/manual walk-ins without a user
   link do not become fabricated customer accounts.
6. There is no new staff-user/permission model, live revenue dashboard, complete
   support ticket system, or subscription grace-period enforcement in this
   iteration. Resource/chair management and existing reports/feedback remain the
   operational foundation. Those larger features need separately scoped data
   and authorization work; no placeholders are presented as working features.
