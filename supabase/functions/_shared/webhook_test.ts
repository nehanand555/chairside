import { Stripe } from "./stripe.ts";
import { verifyStripeWebhook } from "./webhook.ts";

Deno.test("webhook accepts the signed raw body and rejects tampering and stale events", async () => {
  const client = new Stripe("sk_test_signature_verification_only");
  const raw = JSON.stringify({ id: "evt_unit", type: "checkout.session.completed", data: { object: {} } });
  const secret = "whsec_unit_test_only";
  const signature = await client.webhooks.generateTestHeaderStringAsync({ payload: raw, secret, cryptoProvider: Stripe.createSubtleCryptoProvider() });
  if ((await verifyStripeWebhook(raw, signature, ["wrong_secret", secret]))?.id !== "evt_unit") throw new Error("Signed event rejected");
  if (await verifyStripeWebhook(raw + " ", signature, [secret])) throw new Error("Tampered event accepted");
  if (await verifyStripeWebhook(raw, signature, ["wrong_secret"])) throw new Error("Wrong secret accepted");
  const stale = await client.webhooks.generateTestHeaderStringAsync({ payload: raw, secret, timestamp: 1, cryptoProvider: Stripe.createSubtleCryptoProvider() });
  if (await verifyStripeWebhook(raw, stale, [secret])) throw new Error("Stale event accepted");
});
