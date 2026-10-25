# spicyself application and backend audit — 26 October 2026

This report distinguishes source/test results from live evidence. No live admin
permissions, reviews, email deliveries or migration records were changed during
the audit. Supabase is installed/enabled in the plugin directory, but its project
tools are not exposed in this session and the CLI has no authenticated account.
The user is connecting Supabase; live privileged verification remains pending.

## Feature results

| Feature | Source/tests | Live environment |
| --- | --- | --- |
| Lowercase branding | PASS: remaining booking labels, generated web/native display names, discovery warnings and email headings fixed; legacy queued email content normalised at rendering | FAIL at initial inspection: mixed-case document title and member badge found on all three domains. Web redeployment verification recorded below; native binaries not verified. |
| Google authentication/session isolation | PASS: OAuth explicitly requests `select_account consent`; installed Auth client removes local session before sign-out request; realtime watcher stopped explicitly; profile/admin/MFA/drafts and late responses have account/session guards | NOT VERIFIED: no real Google account logout/switch was performed |
| Admin security | PASS locally: verified Auth-owned approved email + private membership + MFA required; wrong member cannot read/review or spoof claims; RLS/grant tests pass | NOT VERIFIED: live memberships, guard definitions and decision actors need authenticated audit. Do not treat this source fix as deployed authorization. |
| Authenticator QR | PASS for local SVG rendering, hidden manual fallback and session guards; `flutter_svg` 2.3.0 and vector dependencies locked; no external QR service | NOT VERIFIED: compiled QR UI exists live, but an actual enrollment and Google/Microsoft scan were not performed. Fixture SVG tests do not prove scannability. |
| NZ business registration | PASS: server restricts suggestions to NZ; details validate country/bounds and populate address/suburb/coordinates/Place ID; client sets map pin; regression tests exercise selection without manual coordinates | FAIL at initial official-domain inspection: Edge preflight is 403. Pages staging preflight is 204. Real authenticated Places lookup not verified. |
| Emails | PASS for template escaping/branding, queue events, claim-once behavior, protected worker, separate acceptance/delivery storage | NOT VERIFIED: secrets, Resend verification, current queue states, deployed versions and real inbox delivery unavailable. Latest historical worker Actions success is not proof of an email being sent. |
| Deployment | PASS locally: clean CLI migration deployment, strict formatter/analyzer/tests, release build; version collision and lockfile issues fixed | Web CI/deployment evidence below. Backend changes have not been deployed by this audit. |

## Confirmed live evidence before audit fixes

- Product checks 40186727743 and staging deployment 40186727805 succeeded for
  `593582de4fe2cb64ec0ce289aeb12ce9f548dbdb`.
- `https://www.spicyself.com`, `https://spicyself.com` and
  `https://chairside-staging.pages.dev` return HTTP 200 with a browser User-Agent.
- All three returned identical `main.dart.js` SHA-256:
  `e3ae084834586b36c2e782dba42da8e07edb302461a595d385e900ffb6ee2ada`.
  The bundle contains QR fallback and business-address UI strings, but also
  `Verified SpicySelf business`. Document title used mixed-case `SpicySelf`.
- Live `discover`, `business-address`, and `business-application-notify`
  preflights return 403 for `https://www.spicyself.com`; the Pages origin returns
  204 with matching CORS headers. The shared handler now explicitly recognises
  the two official HTTPS origins while retaining authentication and rejecting
  lookalike/HTTP origins. This fix requires Edge Function deployment.
- Anonymous `admin_overview`, `admin_email_events`, and
  `my_pending_business_application` RPC calls return 401 / PostgreSQL 42501.
  This verifies anonymous denial, not denial of the reported signed-in account.
- An email-worker call without worker/cron credentials returns 401 and sends no mail.

## Admin investigation and correction

The previous backend guard trusted any UUID in `private.admins` plus an `aal2`
claim. It did not constrain that membership to the explicitly authorised email.
`account_context` exposed that membership as `is_admin` before MFA. Recent UI
changes prevent cached roles crossing accounts; they cannot replace a database
authorization guard or prove who performed a historical decision.

New `private.admin_identity_allowed()` checks membership against `auth.users`:
`spicynetwork75@gmail.com`, confirmed email, no deleted or blocked account.
`private.is_admin()` additionally requires `aal2`. `account_context` uses the
same identity guard so the authorised account can enrol MFA without granting
review privileges before verification. No new admin member is granted, MFA is
not bypassed, and users cannot call the private identity helper directly.

`supabase/tests/admin_security.sql` deliberately gives the reported other account
private admin membership and an aal2 claim. Overview, health, email controls,
approve/reject/suspend, and RLS access are denied even with forged email/user
metadata claims. The authorised member succeeds only with MFA; absent membership,
unconfirmed email and blocked status are denied. Decision audits are asserted.

Run `supabase/live_audit_readonly.sql` using authorised access to determine whether
an unintended membership exists and which identity actually performed reviews.
Do not conclude that the reported account performed reviews from UI visibility
alone. Do not remove or rewrite live audit records.

## Notifications: implemented events versus templates

The transactional database outbox queues applicant acknowledgement, admin
application alert, updated admin application alert, and approved/rejected/
suspended owner decisions. SQL regression tests prove queue insertion and
service-only claiming; the worker sends through Resend and the signed webhook
records delivery outcomes. Provider acceptance is not inbox delivery.

Booking confirmations, queue updates, cancellations and reminders have HTML/text
presentations but no customer-email enqueue path in the current outbox, whose
schema is business-specific. They must not be advertised as active customer
email delivery. Supabase Auth email sign-in is a separate provider configuration,
not this outbox. Existing booking SMS/refund processing is separate. SMS text now uses lowercase
spicyself and the current My Bookings navigation; SMS send eligibility and
provider configuration are unchanged.

The active worker imports `email_templates.ts`; older review helper/admin HTML
functions are legacy paths. Main links default to `https://www.spicyself.com`;
admin routing can be overridden with server-only `SPICYSELF_ADMIN_URL` and its
live value has not been read. Links open the app and describe navigation, not a
pre-authorised approval URL. No real emails were sent during these tests.

## Migration deployment defect

A real clean `supabase db push` against the disposable database failed with
`schema_migrations_pkey`: both scheduler and outbox used version
`20261025090000`. The scheduler now has a CLI-generated unique version; outbox
retains the original version. A subsequent clean CLI deployment succeeds.
`tool/migrations_test.py` prevents duplicate versions from recurring.

IMPORTANT FOR EXISTING PROJECTS: inspect managed migration history and schema
before a backend deploy. If the legacy version is recorded for the scheduler,
verify that the outbox schema was installed separately. A clean deployment test
does not prove an existing project's history is aligned. Do not blindly mark
versions applied or replay historical backfills. Live reconciliation is pending.

## Validation

- `flutter pub get`: passed; lock includes flutter_svg 2.3.0, path_parsing,
  vector_graphics, vector_graphics_codec, vector_graphics_compiler and compatible xml.
- `dart format --output=none --set-exit-if-changed lib test`: passed after fixing
  six existing formatting differences. CI now enforces the same strict check.
- `flutter analyze`: passed.
- `flutter test`: 48 passed, including an additional cached-profile identity test.
- Python tool checks: 10 passed (branding, bootstrap, deployment ownership, migration versions).
- Deno shared tests: 16 passed; all 9 Edge Function entrypoints type-check.
- PostgreSQL 17.10 disposable database: full migrations via Supabase CLI passed;
  core/integrations/Google auth/admin security/email outbox suites passed, with
  54 labelled assertions. Supabase-specific Cron/Vault setup is intentionally
  skipped locally and is not verified by these tests.
- Supabase CLI security advisors against the disposable database at error level:
  no findings. Direct catalogue inspection: all public tables have RLS; clients
  have no direct business mutations or private admin table grants. This is not
  a production advisor result or a claim of no lower-severity findings.
- Release Flutter web build passed. Existing Cupertino font warning remains.
- Native mobile build/install, real OAuth/MFA/Places, payments, live Auth settings,
  Cloudflare account settings and provider delivery events are NOT VERIFIED.

## Configuration required for live verification

Read server metadata without exposing values: allowed origins, function versions,
Auth site/redirect URLs, Google provider enablement, service-role boundaries,
GOOGLE_PLACES_KEY availability/Places API permission, worker/cron setup, sender
verification and webhook configuration. Client Google Maps and Supabase public
keys must not be confused with server credentials. Local key files remain ignored.

## Commits and deployment follow-up

The preceding lock repair was committed and deployed as `593582d`. This audit's
fixes and final live web verification are recorded in the follow-up below.
Backend migrations, CORS/email function changes and config changes remain pending
until authenticated project access and migration-history review are available.

## Audit commits and CI follow-up

- `5117fb3`: source/backend hardening, branding, migration fix, SQL tests and report.
- `1d5831d`: included the locally validated regression/formatting files and added
  only ALLOWED_ORIGINS to Deno test permissions. Initial audit CI correctly blocked
  deployment until these omissions were corrected; database checks passed.
- Final SMS branding/package-description follow-up is included with this report.
- PostgreSQL booking concurrency tests also passed against real disposable
  connections using a temporary pg client command adapter (system psql absent).
- Future web deployments expose version.json containing only the source commit.
  Backend fixes remain undeployed until live connection/history review completes.
