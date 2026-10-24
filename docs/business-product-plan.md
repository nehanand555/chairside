# SpicySelf — product and revenue plan

## Positioning
SpicySelf helps customers discover nearby barbers, salons and independent/home-based professionals, and helps verified businesses turn discovery into bookings and repeat visits. Launch in Wellington / Lower Hutt before expanding.

## Customer experience (free)
- Discover nearby professionals through map and search.
- View transparent business information, services, prices and booking links.
- External listings: link to the business's existing website or booking page; never claim availability without an authoritative source.
- Verified SpicySelf businesses: book appointments or join a live queue, view visit status.

## Business experience
- Free: claim/register listing, verify ownership, manage profile, services, prices, opening hours and website/booking URL.
- Proposed Pro ($29 NZD/month, subject to customer validation): appointment and queue management, reminders, customer history and basic analytics.
- Proposed Growth ($59 NZD/month, subject to validation): waitlists, rebooking tools and richer insights.
- Multi-location plans only after demand is demonstrated. Never restrict existing free listing functionality without explicit product and customer review.

## Revenue architecture
Keep listing verification independent of subscription status. Add server-validated entitlements and billing webhooks before introducing paid-only features. Do not trust a client-side `is_pro` flag. Payment processing and taxes require provider configuration and commercial/legal review. No live billing until the pricing model is validated with pilot businesses.

## Delivery phases
1. Reliability: Flutter CI green, stable sign-in/navigation, external links, booking and queue tests, production/staging separation.
2. Onboarding: business claim/application, registration/contact verification, admin review, notification delivery and explicit approval.
3. Business value: daily dashboard, appointments, queue, staff/chair allocation, hours, reminders and no-show management.
4. Monetisation: billing provider, subscription plans, webhook verification, entitlement enforcement, failure handling and cancellation.
5. Pilot: recruit 10 Wellington/Lower Hutt businesses, measure completed bookings, active owners, repeat customers, paid conversion and churn.

## Immediate acceptance criteria
- CI tests and deployment checks pass before treating changes as released.
- Business applications persist and appear in the admin review queue even if email delivery fails.
- Admin email delivery is verified end to end using configured secrets; never hard-code email service credentials.
- A business cannot self-approve or manage another business.
- External booking links remain available for businesses not yet registered.
- A free listing has no implied payment obligation.

## Success measures
Prioritise completed bookings, active businesses, owner retention, repeat customer bookings and paid conversions over app installs. Proposed first milestone: 10 pilot businesses; then 5–10 paying owners if pilot feedback supports a subscription.
