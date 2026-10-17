# Google Maps and barber discovery

Google sign-in and Google Maps/Places use different credentials. Signing in successfully does not connect public barber listings. A fresh project has no Chairside members until an owner applies and is approved; public Google listings do not require joining Chairside.

## Configure the two web services

1. In your own Google Cloud **Chairside** project, link a billing account for Maps Platform. Review current pricing before enabling it. Google provides SKU-specific monthly free usage allowances; usage beyond them is billed. This is not an unlimited free service. Billing budgets are alerts, not hard spending caps.
2. Enable **Places API (New)** and **Maps JavaScript API**.
3. Create a server key named **Chairside Places server**. Restrict its API access to **Places API (New)**. Store it in Supabase → Edge Functions → Secrets as `GOOGLE_PLACES_KEY`. Never put this key in the Flutter configuration, a browser referrer-restricted key field, public repository variables or chat. If an appropriate stable egress IP is available, restrict it to that server IP; ordinary managed Edge Functions do not provide a single fixed egress IP by default.
4. Create a separate browser key named **Chairside web map**. Set **Websites / HTTP referrers** to `https://chairside-staging.pages.dev/*`. Restrict its API access to **Maps JavaScript API**. Add it to GitHub → staging → Environment variables as `GOOGLE_MAPS_WEB_KEY`. This key is public client configuration, protected by referrer/API restrictions.
5. Configure low provider-side API quotas, usage monitoring and budget alerts before sharing the site. The backend also rate limits search requests through `DISCOVERY_DAILY_LIMIT` (default 250/day); this alone is not a complete billing cap and does not limit map loads. For a small initial pilot, set the Supabase secret `DISCOVERY_DAILY_LIMIT=100` and review the corresponding provider quotas.
6. Deploy **backend** from `main` to `staging`, then build a fresh configured **web** package. Upload the folder containing `index.html` as a new Cloudflare Pages production deployment for the staging project. A browser key added after a build is not present in an already-uploaded Flutter bundle.

Keep the existing Supabase `ALLOWED_ORIGINS=https://chairside-staging.pages.dev` and a long random `RATE_LIMIT_SALT` configured. Credentials never belong in a screenshot or chat. Mobile map SDKs need their own enabled APIs and platform-restricted keys later; web keys should not be reused for native apps.

## Expected results

- **Near me** asks for browser/device location permission and uses that center for a Google Nearby Search of barbers and salons. Location services/permission must be allowed; a suburb or postcode search remains available when location is off.
- A **suburb, town or postcode** (for example `5014`) sends a New Zealand text search to Google even when no Chairside business is registered there. Retry repeats the same text query, and failed searches clear old listing results.
- When the map cannot render, successful Google results can still appear as an attributed list. Google results remain separate from Chairside members and are not persisted.
- A missing Places key reports that Google listings are not connected. A valid server key plus a failed upstream request reports that Google listings are temporarily unavailable. Neither state means Google has no barbers in that town.
- Google listings offer details/directions. Only approved Chairside members offer bookings, queue estimates and verified service prices. Home studios can register directly from Business without a Google listing.

Test the deployed site with location allowed and denied, a postcode, a suburb, an empty Google response, and a temporary Google error. Verify Google pins and listing attribution on mobile and desktop before release.

Official setup/pricing/policies:
- https://developers.google.com/maps/documentation/places/web-service/get-api-key
- https://developers.google.com/maps/documentation/javascript/get-api-key
- https://developers.google.com/maps/billing-and-pricing/pricing
- https://developers.google.com/maps/documentation/places/web-service/policies
