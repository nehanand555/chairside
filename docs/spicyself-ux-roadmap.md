# spicyself: product experience roadmap

Design standard: original spicyself forest-green/cream identity; benchmark convenience and accessibility against Fresha, Mangomint and Square Appointments without copying their branding, layouts or assets.

## What is already implemented
- Customer discovery and external booking links for non-member businesses.
- Business review, basic services, hours, appointments, queue and calendar.
- Dedicated membership/billing page; NZ$49.99 Stripe price behind disabled checkout flag.
- Professional portraits: each resource may have a photo_path in the existing portfolios bucket; clients can see avatars when choosing a barber or technician. Uploaded media is associated with the business and professional ID and photo links are managed by the owner-validated MFA-protected RPC.

## High-priority improvements (not yet complete)
1. **Customer book in under 60 seconds:** service picker with durations/prices; choose professional or any available; best next available times; frictionless review; confirmations, rescheduling and rebooking.
2. **Solo and home-studio onboarding:** category-specific wording (hair, nails, lashes, brows, waxing, facials), sensible one-person defaults, protect residential addresses, provide shareable booking link.
3. **Merchant day view:** calendar with staff columns, breaks, availability, upcoming client info and one-tap status changes. Separate bookings from walk-in queue.
4. **Professional profiles:** add optional biography, specialties/service assignments, working hours and portfolio; avoid assigning services or employees to generic chairs.
5. **Business operations:** clients, reminders, waitlist, booking policies, cancellation and no-show tools; do not collect or show more personal data than needed.
6. **Admin:** MFA-verified server-side admin authorization, business reviews, subscriptions, audit log, email delivery and support tickets. Regression-test account-switch isolation.
7. **Payments:** live customer checkout remains off until Stripe Connect direct charges, refunds/webhooks and reconciliation are proven. Membership checkout is separately gated. Do not enforce paywall against existing approved businesses until a rollout/grace-period policy is adopted.
8. **Accessibility/performance:** responsive compact mobile layout; keyboard and screen reader support; form validation; skeleton/error states; offline/latency messaging; role-based widget and end-to-end tests.

## Acceptance criteria
- A customer can reliably find a real, approved business and book a truly available appointment; server prevents double bookings even under concurrent requests.
- A home-based technician can publish a suburb-level listing without exposing a residential street address to browsing customers.
- Owners can upload, replace and remove profile portraits, and the same photo appears in public booking where appropriate; unauthorised users cannot modify other businesses.
- A merchant can clearly distinguish membership billing from charges payable by their own clients.
- A platform administrator cannot be impersonated through a client-only role change or session switch.
- CI passes Flutter analysis, formatting, widget/unit tests and authorization tests before any production deployment.

## Deployment safety
Implement in small reviewed commits. Validate migrations/permissions in staging and confirm real availability results; do not fabricate customer ratings, availability, revenue or reviews. Keep production Stripe charges and automatic production deployment off until separately approved.
