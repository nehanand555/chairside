import { env, rpc, service } from "../_shared/http.ts";
import { processRefunds, Stripe } from "../_shared/stripe.ts";
import { verifyStripeWebhook } from "../_shared/webhook.ts";

Deno.serve(async req => {
  if (req.method !== "POST") return new Response("Use POST", { status: 405 });
  const raw = await req.text();
  const verified = await verifyStripeWebhook(raw, req.headers.get("stripe-signature") ?? "", [env("STRIPE_WEBHOOK_SECRET"), Deno.env.get("STRIPE_CONNECT_WEBHOOK_SECRET")].filter((s): s is string => Boolean(s)));
  if (!verified) return new Response("Invalid signature", { status: 400 });
  const event = verified;
  try {
    if (event.type === "checkout.session.completed" || event.type === "checkout.session.async_payment_succeeded") {
      const session = event.data.object as Stripe.Checkout.Session;
      if (session.payment_status === "paid" && session.metadata?.chairside_session) {
        const intent = typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id;
        if (!intent) throw new Error("Missing payment intent");
        await rpc(service(), "integration_paid", { p_event: event.id, p_session: session.metadata.chairside_session, p_intent: intent, p_amount: session.amount_total, p_currency: session.currency });
        await processRefunds();
      }
    } else if (event.type === "account.updated") {
      const account = event.data.object as Stripe.Account;
      await rpc(service(), "integration_sync_account", { p_account: account.id, p_enabled: account.charges_enabled && account.payouts_enabled });
    } else if (event.type === "refund.updated" || event.type === "refund.created") {
      const refund = event.data.object as Stripe.Refund;
      if (refund.status === "succeeded") await rpc(service(), "integration_refund_event", { p_intent: refund.payment_intent, p_refund: refund.id, p_amount: refund.amount });
    }
    return new Response(JSON.stringify({ received: true }), { headers: { "content-type": "application/json" } });
  } catch { return new Response("Event processing failed; retry required", { status: 500 }); }
});
