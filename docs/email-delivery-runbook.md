# Email delivery deployment runbook

## Deployed components
- `private.email_outbox` queues admin application alerts, applicant acknowledgements and admin decisions transactionally.
- `email-worker` sends queued messages via Resend; it requires a strong `WORKER_SECRET` in `x-worker-secret`. The worker returns 503 without Resend configuration **before** claiming messages.
- `resend-webhook` validates signed delivery callbacks using `RESEND_WEBHOOK_SECRET`.
- `business-application-notify` acknowledges queued state and no longer sends directly.
- Admin UI includes delivery counts, last 50 event statuses and guarded retries of HTTP-rejected messages.

## Required setup before mail actually flows
Supabase Edge secrets:
`WORKER_SECRET`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL` (verified sender), `APPLICATION_REVIEW_EMAIL` (admin inbox), `RESEND_WEBHOOK_SECRET`. Ensure existing `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are available to the Edge runtime.

GitHub repository Actions secrets:
`SPICYSELF_SUPABASE_URL` = `https://nylhyzveicmgqmckveyr.supabase.co`
`SPICYSELF_WORKER_SECRET` = the same value as Edge `WORKER_SECRET`.

Resend webhooks: add endpoint `https://nylhyzveicmgqmckveyr.supabase.co/functions/v1/resend-webhook` and subscribe to delivered, bounced, failed and complained events. Set its signing secret as `RESEND_WEBHOOK_SECRET`.

GitHub Actions scheduled workflows only run on default branch. Merge branch after validation to activate five-minute scheduling. The cron service may delay runs.

## Operation and safety
- Inspect `select event_type,state,count(*) from private.email_outbox group by 1,2;` using an administrator database connection. Avoid copying recipient addresses into logs.
- Verify Resend sender DNS SPF/DKIM and delivery events, not just accepted status.
- HTTP 429 and 5xx are retried with exponential delay (max five attempts); ambiguous timeouts and interrupted sends are held as `failed` for manual reconciliation to avoid duplicate messages.
- Administrative retries are only offered for known provider HTTP rejections, never ambiguous outcomes.
- On provider outage, leave outbox intact. Don't manually flip failed to pending without checking the provider.
- If webhook secrets or scheduler secrets are not configured, accepted deliveries cannot be confirmed and automation will not operate.

## Limitations
- Tests in `application_notification_test.ts` cover the older HTML helper; worker and webhook integration tests and full Flutter CI must pass before declaring release proven.
- The legacy `notification_sent_at` field is retained for compatibility, not used as the outbox's delivery status.
- The workflow needs GitHub Actions secrets before it can process mail.
