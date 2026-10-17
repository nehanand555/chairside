# Chairside

A connected Flutter application for Android, iOS and web, with Supabase as the shared backend. Customers discover New Zealand hair professionals, book appointments or join a live queue. Business owners manage chairs, services, hours, breaks, walk-ins and visits. Admins review applications and handle reports/refunds.

This branch replaces the in-memory prototype. **External services are not activated by uploading code.** Without Supabase configuration the app displays a connection/setup notice and does not invent businesses or bookings.

## First activation step

Create a Supabase project you own. In GitHub → Settings → Environments, create `staging`. Add its URL and publishable key as `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` variables. Never use a service-role/secret key in Flutter or a GitHub variable. Continue with [service activation](docs/activation.md) once that project exists.

## Run and build

Use Flutter **3.47.7**. From the repository root, set the public configuration values shown in `.env.example` in your terminal environment, then:

```sh
python3 tool/bootstrap.py
flutter pub get --enforce-lockfile
flutter run -d chrome --web-port=3000 --dart-define-from-file=build-config.json
```

The bootstrap script generates the Android/iOS/web platform shells and adds map/location/photo settings. It never replaces application code or tests. Platform shells and generated client configuration are ignored by Git. Run the script again when public keys change. Choose a permanent bundle ID in `tool/bootstrap.py` before app-store registration; the initial ID is `nz.chairside.chairside`.

GitHub Actions → **Product checks** runs analysis, UI tests, PostgreSQL permission/booking tests and server-function checks. **Build app packages** produces a web bundle, Android test APK or iOS simulator app. iPhone installation and store releases need your Apple/Google developer accounts and signing configuration; a simulator build is not an App Store release.

**Deploy configured services** is manual, runs checks first, and uses the selected GitHub environment. It deploys Supabase migrations/functions or a configured Cloudflare Pages web project. Production is not deployed automatically on merge. Protect the `production` environment with required reviewers.

## Data and security

PostgreSQL is authoritative: transaction locks, interval constraints, RLS and protected RPCs enforce booking and ownership rules. The UI never assigns an admin role or marks a payment paid. Phone OTP is used for customer accounts; authenticator MFA is required for business/admin operations. Home addresses are private; public searches use approximate home coordinates only. Photos are deliberately public.

Google Places directory results are fetched live, kept separate from Chairside member listings, and are not persisted. A Google listing alone never enables booking. Payments use Stripe-hosted Connect/Checkout and signed webhooks; no card details are stored. SMS uses a durable outbox and a scheduled worker. See [operations](docs/operations.md) for backups, monitoring and release checks.

Initial product scope: one owner account per business, up to 20 chairs, common weekly opening hours, appointments and same-day queues, full refunds, SMS updates and portfolio photos. Individual employee accounts, push notifications, recurring/overnight schedules, partial refunds, subscriptions and automated business verification are not implemented. Business approval is a manual platform review. No production launch or device/payment-provider certification is implied by passing CI.
