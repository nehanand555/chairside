import { service } from "./http.ts";
import { stripe, Stripe } from "./stripe.ts";
import { validMembershipPrice, membershipPeriodEnd, invoiceSubscriptionId } from "./membership_policy.ts";

export type BillingDependencies = {stripe: typeof stripe; service: typeof service};
const defaultDependencies: BillingDependencies = {stripe,service};

function stripeId(v: string | { id: string } | null | undefined): string | null {
  return typeof v === "string" ? v : v?.id ?? null;
}
function allowedStatus(status: string): boolean {
  return ["incomplete","incomplete_expired","trialing","active","past_due","canceled","unpaid","paused"].includes(status);
}
async function syncSubscription(subId: string, expectedBusinessId: string | undefined, dependencies: BillingDependencies): Promise<boolean> {
  // Retrieve current authoritative state to tolerate out-of-order events.
  const sub = await dependencies.stripe().subscriptions.retrieve(subId);
  if (sub.metadata?.spicyself_kind !== "business_subscription") return false;
  if (!allowedStatus(sub.status)) throw Error("Unsupported Stripe subscription status");
  // An active subscription on another Stripe price must not unlock the paid
  // business membership (e.g. the earlier NZ$0 placeholder product).
  if (sub.items.data.length !== 1 ||
      !sub.livemode || !validMembershipPrice(sub.items.data[0].price, {requireActive:false}) ||
      sub.items.data[0].quantity !== 1) {
    throw Error("Unexpected spicyself membership price");
  }
  const businessId = sub.metadata.spicyself_business_id;
  if (!businessId || (expectedBusinessId && expectedBusinessId !== businessId)) throw Error("Business mismatch");
  const customerId = stripeId(sub.customer);
  if (!customerId) throw Error("Missing Stripe billing customer");
  const db = dependencies.service();
  const { data: row, error: readError } = await db.from("business_subscriptions")
    .select("business_id,stripe_customer_id,stripe_subscription_id")
    .eq("business_id", businessId).eq("stripe_customer_id", customerId).maybeSingle();
  if (readError || !row) throw Error("Unrecognised business billing customer");
  if (row.stripe_subscription_id && row.stripe_subscription_id !== sub.id) {
    // A stale, cancelled subscription must not overwrite the newer contract.
    return true;
  }
  const period = membershipPeriodEnd(sub);
  const { error } = await db.from("business_subscriptions").update({
    stripe_subscription_id: sub.id,
    status: sub.status,
    price_id: sub.items.data[0]?.price.id ?? null,
    current_period_end: period,
    cancel_at_period_end: sub.cancel_at_period_end,
    updated_at: new Date().toISOString(),
  }).eq("business_id", businessId).eq("stripe_customer_id", customerId);
  if (error) throw Error("Unable to persist verified subscription");
  return true;
}

/** Returns true when the event belongs to spicyself subscription billing. */
export async function processBusinessBillingEvent(event: Stripe.Event, dependencies: BillingDependencies = defaultDependencies): Promise<boolean> {
  if (event.account) return false; // Subscriptions belong to the platform, not Connect merchants.
  if (event.type === "checkout.session.completed") {
    const session = event.data.object as Stripe.Checkout.Session;
    if (session.mode !== "subscription" || session.metadata?.spicyself_kind !== "business_subscription") return false;
    const businessId = session.metadata.spicyself_business_id;
    const customerId = stripeId(session.customer);
    const subId = stripeId(session.subscription);
    if (!businessId || !customerId || !subId) throw Error("Missing subscription checkout identifiers");
    const db = dependencies.service();
    const { data: row, error } = await db.from("business_subscriptions")
      .select("business_id")
      .eq("business_id", businessId)
      .eq("stripe_customer_id", customerId)
      .eq("stripe_checkout_session_id", session.id).maybeSingle();
    if (error || !row) throw Error("Unrecognised subscription checkout");
    await syncSubscription(subId, businessId, dependencies);
    return true;
  }
  if (event.type === "customer.subscription.created" ||
      event.type === "customer.subscription.updated" ||
      event.type === "customer.subscription.deleted") {
    const sub = event.data.object as Stripe.Subscription;
    if (sub.metadata?.spicyself_kind !== "business_subscription") return false;
    await syncSubscription(sub.id, undefined, dependencies);
    return true;
  }
  if (["invoice.paid", "invoice.payment_failed", "invoice.payment_action_required"].includes(event.type)) {
    const subId = invoiceSubscriptionId(event.data.object as Stripe.Invoice);
    if (subId) return await syncSubscription(subId, undefined, dependencies);
  }
  return false;
}
