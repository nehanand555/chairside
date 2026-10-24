import { deliverReviewEmail, ReviewEmail } from "./application_notification.ts";

const email: ReviewEmail = {apiKey: "unit-test-only", from: "Review <review@example.invalid>",
  to: "admin@example.invalid", businessId: "application-unit", businessName: "Test studio", text: "Application for review"};

Deno.test("application email retries reuse a stable provider idempotency key", async () => {
  const keys: (string | null)[] = [];
  const request: typeof fetch = (_url, options) => {
    keys.push(new Headers(options?.headers).get("Idempotency-Key"));
    return Promise.resolve(new Response(null, {status: 202}));
  };
  await deliverReviewEmail(email, request);
  await deliverReviewEmail(email, request);
  if (keys.length !== 2 || keys.some(k => k !== "business-application/application-unit"))
    throw new Error("Retry idempotency key changed");
});

Deno.test("rejected and unreachable email sends report saved application without leaking provider details", async () => {
  for (const status of [403, 429, 503, 0]) {
    let failed = false;
    try {
      await deliverReviewEmail(email, () => status === 0
        ? Promise.reject(new Error("sensitive-provider-detail"))
        : Promise.resolve(new Response("sensitive-provider-detail", {status})));
    } catch (error) {
      failed = true;
      const message = (error as Error).message;
      if (!message.includes("Application saved") || message.includes("sensitive-provider-detail") || message.includes(email.apiKey))
        throw new Error("Unsafe or misleading notification failure");
    }
    if (!failed) throw new Error("Rejected delivery was treated as accepted");
  }
});
