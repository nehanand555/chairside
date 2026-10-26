# Sign in with Apple setup

The Flutter Apple OAuth action is intentionally hidden until the Supabase provider is configured. This avoids showing a broken login button.

1. In Apple Developer, register a **Services ID** for the web OAuth domain `nylhyzveicmgqmckveyr.supabase.co` and register the redirect/return URL `https://nylhyzveicmgqmckveyr.supabase.co/auth/v1/callback`. Enable Sign in with Apple and associate it with the app's primary App ID as Apple requires.
2. Create an Apple Sign in with Apple key, then configure the Apple provider in Supabase Dashboard → Authentication → Providers → Apple. Supply the Services ID, Team ID, Key ID and signed client secret as requested by Supabase. Keep the private key and client secret out of GitHub and all public Flutter build files. Apple OAuth secrets require periodic rotation.
3. Confirm Supabase Authentication → URL Configuration includes `https://www.spicyself.com/` and the mobile deep link `nz.nehanand.spicyself://login-callback/` if supporting mobile browser OAuth.
4. Set GitHub **environment variable** `APPLE_SIGN_IN_ENABLED=true` for the target web deployment environment only after the Apple provider and signed JWT client secret are configured. Deployment workflow passes this flag through `tool/bootstrap.py` to `build-config.json`. Otherwise the Apple button is hidden.
5. After deployment, test on Safari and another browser and confirm an Apple sign-in lands in the correct account. An existing Google user may create a separate identity when switching providers: test account linking carefully before offering this as a login alternative to existing businesses.

Apple OAuth is a sign-in method, not a replacement for the MFA AAL2 requirement on privileged business/admin operations. For a future iOS-native implementation consider the Apple native authentication APIs rather than a browser OAuth redirect.

To publish a newly configured flag in staging, push to `main` (which triggers the staging web deploy) or dispatch `.github/workflows/deploy.yml` with target `web` and environment `staging`.
