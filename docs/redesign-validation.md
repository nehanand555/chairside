# SpicySelf marketplace redesign

## Architecture and scope

One Flutter application serves customers and owners. Explore, Map, My Bookings
and Profile are the four customer destinations. Explore and Map share one
discovery state, including search results, category and favourite filters; tab
switches do not make another Places request. Admin is a protected route from
Profile, not a customer destination.

The redesign keeps the existing Supabase auth/PKCE callbacks, database RPCs,
RLS, Stripe boundaries, realtime visit refresh and New Zealand time/currency
handling. No schema migration or live service change is required for the UI.
The existing `require_operator` and admin RPC checks remain authoritative;
client visibility and badges never grant access. Pending/rejected/suspended
owners cannot load management data, and approved owners still need MFA.

The repository review covered Flutter screens/store/backend, migration and
permission contracts, discovery/payment/notification Edge Functions, native
bootstrap, existing tests and Actions workflows. The initial staging request through the web tool was inaccessible. A later
headless Chrome visit succeeded: the existing directory, live Google map and
old navigation were visually reviewed. That was the existing deployment, not
this local redesign.
The local web release was visually reviewed in headless Chrome with an emulated
390×844 viewport. Live discovery returned Service unavailable on localhost; the
review covered responsive layout and the graceful error state, not successful
live listings.

## Customer experience

- Shared green/cream/lime theme, original scissors artwork, reusable cards,
  placeholders, status pills, skeletons, form fields and section headings.
- Explore has location search, optional Near me, member categories, saved-place
  filtering, a map entry and responsive business cards. Categories filter
  members; All also shows unclassified public Google results.
- Map has green member markers, public directory markers, selected-marker
  previews, recenter and search-this-area controls. Missing configuration or
  denied location permission leaves list/suburb search available.
- No invented ratings, distances, stock photography, featured ranking or
  appointment availability. Discovery returns approved members only. A missing
  distance is omitted, not replaced with zero.
- Public Google results remain labelled and attributed. External booking needs
  an actual booking-specific URL. They never receive member booking controls.
- Member detail includes real portfolio images with fallbacks, hours, services,
  a favourite action and the existing real-time booking/queue flow.
- My Bookings separates Upcoming, Completed and Cancelled. No-show and other
  terminal non-completed records appear under Cancelled, retaining their actual
  status on the card. Pagination, refunds, payment and cancellation actions
  retain existing rules.
- Home studios show a suburb and approximate public pin. Their exact address is
  still obtained only through the protected visit-location RPC.

## Owner and admin experience

Profile has a prominent SpicySelf for Business entry. Applications have four
validated stages: Business, Contact, Location and Review. Owners without a
registration number may explicitly enter `Not applicable`; a human reviewer
decides whether the supplied details are sufficient. Contact/registration
information remains in the existing private application table.

Owners see pending/rejected/suspended status and review notes. A saved
application is not submitted again when notification delivery fails. An
authenticated retry is available from the pending screen. Notification outcome
messages are session-local; the database acknowledgement remains authoritative.

Approved owners get upcoming appointments, a live queue, real visit counts and
expandable sections for services/prices, hours, chairs/breaks, portfolio and
payments. Identity/address changes remain subject to the existing reviewed
replacement-listing process; this redesign does not add an unsafe self-service
identity update RPC.

Admin requires the server-provided admin role and MFA before loading private
applications. It filters businesses by status, validates review notes at
10–2000 characters and retains server-side audited review, reports,
visits/refunds and operational health checks. Email acceptance is not inbox
delivery; existing health counters cover SMS/refunds, not Resend delivery.

## Review email configuration

Set `RESEND_API_KEY`, `RESEND_FROM_EMAIL` and `APPLICATION_REVIEW_EMAIL` only in
Supabase Edge Function secrets. Use a sender on your own Resend-verified domain,
with the required DNS verification completed. `onboarding@resend.dev` is a test
sender with provider recipient restrictions, not a production sender.

Application saving and email sending remain independent. The provider request
now has an application-specific idempotency key to reduce duplicate delivery on
concurrent/retried requests. Resend retains idempotency keys for 24 hours; this
is not an indefinite exactly-once guarantee. The database is acknowledged only
after provider acceptance, and rejected/rate-limited sends remain retryable.
No resources were provisioned and no real email was sent during development.
The modified notification function needs a separately authorised backend
deployment to take effect; the web UI works with its existing response format.

Provider references:
- https://resend.com/docs/dashboard/domains/introduction
- https://resend.com/docs/dashboard/emails/send-test-emails
- https://resend.com/docs/dashboard/emails/idempotency-keys

## Native setup and local iPhone run

Use Flutter 3.47.7. Bootstrap is idempotent, preserves existing client config
when corresponding environment variables are absent, retains the local Maps
key and signing/team settings, and does not lower an existing iOS deployment
target above 15. It repairs the old commented-out Podfile platform declaration.
The existing project disables Swift Package Manager in pubspec configuration;
Google Maps still relies on CocoaPods. Existing local project SPM references
can nevertheless produce a dependency-graph failure; no speculative project
surgery or certificate changes were made.

Keep public Supabase values in Git-ignored `build-config.json` and the native
Maps SDK key in Git-ignored `ios/Flutter/Maps.local.xcconfig`:

```sh
python3 tool/bootstrap.py --platform=ios
flutter pub get --enforce-lockfile
cd ios
pod install
cd ..
flutter devices
flutter run -d YOUR_IPHONE_DEVICE_ID --dart-define-from-file=build-config.json
```

Unlock and trust the iPhone, enable Developer Mode where required, and select
your existing signing team in Xcode for bundle ID `nz.nehanand.spicyself`.
Bootstrap does not create certificates or configure an Apple developer account.

## Validation and remaining limits

- `dart format lib test`: completed.
- `flutter analyze`: no issues.
- `flutter test`: 22 passed, including navigation, map fallback/shared discovery,
  listing distinctions, external link rules, application steps/retries,
  ownership/approval/MFA gates, booking groups and narrow/large-text layouts.
- Python bootstrap/branding/deployment tests: 9 passed.
- Deno check: all six Edge Function entrypoints passed.
- Deno shared tests: 8 passed.
- Flutter web release: built locally. Existing Cupertino font warning remains.
- iOS simulator build: blocked by Xcode dependency-graph response failure,
  exit 255; native Google Maps also emits its existing SPM support warning.
- Android compile not run: local Android SDK is unavailable.
- PostgreSQL/security/concurrency suite not run locally: PostgreSQL and Docker
  are unavailable. Its SQL tests and migrations remain unchanged in CI.
- Live OAuth, Maps, Stripe, location permissions and email delivery still need
  device/provider smoke checks with configured accounts.

Phase commits are local. This redesign was not pushed or deployed to staging
or production. No live credentials, real data or production resources changed.
