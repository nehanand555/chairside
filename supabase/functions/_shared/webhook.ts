import { Stripe } from "./stripe.ts";

// Signature verification is local cryptography; no Stripe API request or secret API key is needed.
export async function verifyStripeWebhook(raw: string, signature: string, secrets: string[]): Promise<Stripe.Event | undefined> {
  const verifier = new Stripe("sk_test_signature_verification_only");
  for (const secret of secrets) {
    try { return await verifier.webhooks.constructEventAsync(raw, signature, secret, undefined, Stripe.createSubtleCryptoProvider()); }
    catch { /* A separate connected-account endpoint may use the next signing secret. */ }
  }
  return undefined;
}
