import Stripe from "npm:stripe@18.5.0";
import { env, rpc, service } from "./http.ts";
export { Stripe };
export const stripe = () => new Stripe(env("STRIPE_SECRET_KEY"), { httpClient: Stripe.createFetchHttpClient(), maxNetworkRetries: 2 });
export async function processRefunds() {
  const client = stripe(), db = service();
  const refunds = await rpc<{ visit_id: string; payment_intent: string }[]>(db, "integration_refunds");
  let processed = 0;
  for (const payment of refunds) {
    try {
      const refund = await client.refunds.create({ payment_intent: payment.payment_intent, reverse_transfer: true }, { idempotencyKey: `chairside-refund-${payment.visit_id}` });
      await rpc(db, "integration_refunded", { p_visit: payment.visit_id, p_refund: refund.id, p_complete: refund.status === "succeeded" });
      processed++;
    } catch { /* Keep refund_pending. It remains visible in visits and is retried with the same key. */ }
  }
  return processed;
}
