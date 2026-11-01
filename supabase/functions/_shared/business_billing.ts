import { service } from "./http.ts";
import { stripe, Stripe } from "./stripe.ts";

function stripeId(v: string | { id: string } | null | undefined): string | null {
  return typeof v === "string" ? v : v?.id ?? null;
}
function allowedStatus(status: string): boolean {
  return ["incomplete","incomplete_expired","trialing","active","past_due","canceled","unpaid","paused"].includes(status);
}
async function syncSubscription(subId: string, expectedBusinessId?: string): Promise<void> {
  // Retrieve current authoritative state to tolerate out-of-order events.
  const sub = await stripe().subscriptions.retrieve(subId);
  if (!allowedStatus(sub.status)) throw Error("Unsupported Stripe subscription status");
  if (sub.metadata?.spicyself_kind !== "business_subscription") return;
  const businessId = sub.metadata.spicyself_business_id;
  if (!businessId || (expectedBusinessId && expectedBusinessId !== businessId)) throw Error("Business mismatch");
  const customerId = stripeId(sub.customer);
  if (!customerId) throw Error("Missing Stripe billing customer");
  const db = service();
  const { data: row, error: readError } = await db.from("business_subscriptions")
    .select("business_id,stripe_customer_id,stripe_subscription_id")
    .eq("business_id", businessId).eq("stripe_customer_id", customerId).maybeSingle();
  if (readError || !row) throw Error("Unrecognised business billing customer");
  if (row.stripe_subscription_id && row.stripe_subscription_id !== sub.id) {
    // A stale, cancelled subscription must not overwrite the newer contract.
    return;
  }
  const period = (sub as unknown as { current_period_end?: number }).current_period_end;
  const { error } = await db.from("business_subscriptions").update({
    stripe_subscription_id: sub.id,
    status: sub.status,
    price_id: sub.items.data[0]?.price.id ?? null,
    current_period_end: period ? new Date(period * 1000).toISOString() : null,
    cancel_at_period_end: sub.cancel_at_period_end,
    updated_at: new Date().toISOString(),
  }).eq("business_id", businessId).eq("stripe_customer_id", customerId);
  if (error) throw Error("Unable to persist verified subscription");
}

/** Returns true when the event belongs to spicyself subscription billing. */
export async function processBusinessBillingEvent(event: Stripe.Event): Promise<boolean> {
  if (event.account) return false; // Subscriptions belong to the platform, not Connect merchants.
  if (event.type === "checkout.session.completed") {
    const session = event.data.object as Stripe.Checkout.Session;
    if (session.mode !== "subscription" || session.metadata?.spicyself_kind !== "business_subscription") return false;
    const businessId = session.metadata.spicyself_business_id;
    const customerId = stripeId(session.customer);
    const subId = stripeId(session.subscription);
    if (!businessId || !customerId || !subId) throw Error("Missing subscription checkout identifiers");
    const db = service();
    const { data: row, error } = await db.from("business_subscriptions")
      .select("business_id")
      .eq("business_id", businessId)
      .eq("stripe_customer_id", customerId)
      .eq("stripe_checkout_session_id", session.id).maybeSingle();
    if (error || !row) throw Error("Unrecognised subscription checkout");
    await syncSubscription(subId, businessId);
    return true;
  }
  if (event.type === "customer.subscription.created" ||
      event.type === "customer.subscription.updated" ||
      event.type === "customer.subscription.deleted") {
    const sub = event.data.object as Stripe.Subscription;
    if (sub.metadata?.spicyself_kind !== "business_subscription") return false;
    await syncSubscription(sub.id);
    return true;
  }
  return false;
}
