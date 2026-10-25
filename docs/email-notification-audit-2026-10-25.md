# SpicySelf email and notification audit — 25 October 2026

**Scope:** GitHub `main`, read-only Supabase inspection of `chairside-staging` (`nylhyzveicmgqmckveyr`), currently deployed `business-application-notify`, and recent Edge Function request logs. **No database mutation, email send, or deployment performed.**

## Evidence

- 2 records in `private.business_applications`; 2 have `notification_sent_at IS NULL`. This is absence of recorded provider acceptance, not proof of nondelivery.
- `business-application-notify` is ACTIVE (deployed version 6). Request logs show HTTP 503 on 2026-10-25 at 07:08:59, 07:39:13 and 07:40:04 UTC. Other calls return 200, which does **not** establish `email_sent=true` because the function also uses HTTP 200 for missing configuration or already-processed messages.
- The deployed shared email helper sends **text only**. GitHub `main` contains an HTML template and a hard-coded link to `https://chairside-staging.pages.dev`; deployed and checked-in implementation differ.
- Required runtime settings for the current admin email flow: `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `APPLICATION_REVIEW_EMAIL`. Their values/presence and Resend domain verification were not available in this audit. No secret values were accessed.
- `claim_business_application_notification` is a **STABLE read-only selection** on an application with null `notification_sent_at`, not an atomic send claim. Parallel calls can both select the same application and send.
- `complete_business_application_notification` only updates the timestamp after provider acceptance; if that database call fails after provider acceptance, later retries may send again (Resend idempotency mitigates only within its supported retention window).
- `update_pending_business_application` resets `notification_sent_at=null`, but the provider idempotency key is derived only from `businessId`. A revised application may therefore reuse the old email request key, potentially preventing the new content from being sent within the provider's idempotency window.
- `admin_review` stores the decision and an audit record but does not enqueue or send owner emails. The Flutter admin screen invokes that RPC without an email sender.
- `private.notification_outbox` is visit/SMS-specific (`visit_id` required by existing design). `notifications` Edge Function processes SMS and refunds; it does not process business application emails.
- Neither a business-application acknowledgement email nor an owner decision email is implemented in the audited paths.
- Current email helper records neither a provider message ID nor delivery/bounce events; HTTP acceptance is not inbox delivery. The currently deployed helper does not send the HTML template in checked-in code.

## Risks and recommended remediations

**P0: User-facing broken admin notification.** Investigate 503 responses and verify sender, allowed recipients, Resend account/domain status, API key permission and CORS. Do not assume an HTTP 200 means success. Confirm response `email_sent` and provider delivery event.

**P1: Reliable transactional outbox.** Add a dedicated `private.email_outbox` with event type, recipient, deduplication key including application revision, state, retry_at, attempt_count, lease, accepted provider message ID, final error code, and created/updated timestamps. Insert events transactionally in application and review RPCs. Use a service-only worker and short leases. For ambiguous provider outcomes, reconcile with the provider before resending, with bounded retries and dead-letter handling. Do not let a user directly set sent/delivered state. Restrict RPC execution, privileges and access.

**P1: Application lifecycle.** Send application acknowledgement, admin review alert, updated application alert, and approved/rejected/suspended decision notifications. Keep database change successful even if asynchronous email fails.

**P1: Delivery status.** Verify and process signed Resend webhooks for `delivered`, `bounced`, `complained` and failed events; make webhook processing idempotent. Save provider message IDs and avoid logging customer contact details or API keys.

**P2: Operations and configuration.** Admin-only delivery dashboard with counts, per-event state, controlled retry, alerting; configurable admin URL and sender; sender DNS SPF/DKIM/DMARC; end-to-end smoke tests using approved test recipients.

## Suggested verification gates before any deployment

1. Pin expected Supabase project, GitHub SHA and deployed function hashes.
2. Add unit tests for provider failures (429, 4xx, 5xx, timeout), duplicate requests, HTML escaping, recipient validation and revision-specific idempotency.
3. Add database tests for single-claim under concurrency, authorization, immutable delivery history, retries, expired lease, and transaction rollback.
4. Run end-to-end test in isolated staging with test recipients and observe webhook deliveries.
5. Review branch and migrations, then deploy only with explicit approval; verify health and rollback plan.

## Partial branch implementation

The audit branch updates the review-email HTML helper to optionally use `SPICYSELF_ADMIN_URL` rather than always using the staging link. This is a **draft code change only**, not deployed. The default remains the existing staging URL for backward compatibility. It does not resolve 503 failures or create the missing email queue.
