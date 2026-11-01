import { authenticated, body, endpoint, HttpError, limited, service, uuid, rpc } from "../_shared/http.ts";
import { stripe } from "../_shared/stripe.ts";

const PRICE_ID = "price_1UWtMV00BuF4kp6TV3uWObsP";
const BASE_URL = "https://www.spicyself.com";
type Billing = {
  business_id: string; stripe_customer_id: string | null;
  stripe_subscription_id: string | null; stripe_checkout_session_id: string | null;
  status: string; current_period_end: string | null; cancel_at_period_end: boolean;
};
const enabled = () => Deno.env.get("ENABLE_BUSINESS_SUBSCRIPTION_CHECKOUT") === "true";

Deno.serve(endpoint(async req => {
  const { user, client } = await authenticated(req);
  await limited(`business-subscription:${user.id}`, 20, 600);
  const data = await body(req);
  const businessId = uuid(data.business_id);
  // The caller's JWT, including AAL2, is checked by the database.
  const listing = await rpc<{ name: string; status: string }>(client, "operator_business", { p_business: businessId });
  if (listing.status !== "approved") throw new HttpError(403, "Business approval is required");
  const db = service();
  const { data: existing, error: readError } = await db.from("business_subscriptions")
    .select("business_id,stripe_customer_id,stripe_subscription_id,stripe_checkout_session_id,status,current_period_end,cancel_at_period_end")
    .eq("business_id", businessId).maybeSingle();
  if (readError) throw new HttpError(503, "Subscription status is temporarily unavailable");
  const billing = existing as Billing | null;
  if (data.action === "status") {
    return {
      plan: "spicyself Business", amount_cents: 4999, currency: "nzd", interval: "month",
      status: billing?.status ?? "not_subscribed",
      current_period_end: billing?.current_period_end ?? null,
      cancel_at_period_end: billing?.cancel_at_period_end ?? false,
      checkout_enabled: enabled(),
    };
  }
  if (data.action !== "checkout" && data.action !== "portal") throw new HttpError(400, "Unknown subscription action");
  // This flag is deliberately off until webhooks, Stripe pricing and existing-
  // business migration are verified. Never charge businesses by default.
  if (data.action === "checkout" && !enabled()) throw new HttpError(503, "Business subscriptions are being prepared. No payment has been taken.");
  const api = stripe();
  if (data.action === "portal") {
    if (!billing?.stripe_customer_id) throw new HttpError(400, "No subscription billing account yet");
    const portal = await api.billingPortal.sessions.create({
      customer: billing.stripe_customer_id,
      return_url: BASE_URL,
    });
    return { url: portal.url };
  }
  if (billing?.status === "active" || billing?.status === "trialing") {
    throw new HttpError(409, "Your subscription is already active. Use Manage billing.");
  }
  // Price is read from Stripe, not trusted from client or from the display.
  const price = await api.prices.retrieve(PRICE_ID);
  if (!price.active || price.currency !== "nzd" || price.unit_amount !== 4999 ||
      price.recurring?.interval !== "month" || price.recurring?.interval_count !== 1) {
    throw new HttpError(503, "The NZ$49.99 monthly subscription price needs verification in Stripe");
  }
  let customerId = billing?.stripe_customer_id;
  if (!customerId) {
    const customer = await api.customers.create({
      ...(user.email ? { email: user.email } : {}),
      name: listing.name,
      metadata: { spicyself_business_id: businessId },
    }, { idempotencyKey: `spicyself-billing-customer-${businessId}` });
    customerId = customer.id;
    const { error } = await db.from("business_subscriptions").upsert({
      business_id: businessId,
      stripe_customer_id: customerId,
      status: "not_subscribed",
      updated_at: new Date().toISOString(),
    }, { onConflict: "business_id" });
    if (error) throw new HttpError(503, "Could not save business billing account");
  }
  if (billing?.stripe_checkout_session_id && billing.status === "checkout_pending") {
    const previous = await api.checkout.sessions.retrieve(billing.stripe_checkout_session_id);
    if (previous.status === "open" && previous.url) return { url: previous.url };
  }
  const session = await api.checkout.sessions.create({
    mode: "subscription",
    customer: customerId,
    client_reference_id: businessId,
    line_items: [{ price: PRICE_ID, quantity: 1 }],
    metadata: { spicyself_kind: "business_subscription", spicyself_business_id: businessId },
    subscription_data: { metadata: { spicyself_kind: "business_subscription", spicyself_business_id: businessId } },
    success_url: `${BASE_URL}/?billing=return`,
    cancel_url: `${BASE_URL}/?billing=cancel`,
  }, { idempotencyKey: `spicyself-subscribe-${businessId}-${crypto.randomUUID()}` });
  const { error } = await db.from("business_subscriptions").update({
    stripe_checkout_session_id: session.id, status: "checkout_pending",
    updated_at: new Date().toISOString(),
  }).eq("business_id", businessId).eq("stripe_customer_id", customerId);
  if (error) {
    await api.checkout.sessions.expire(session.id);
    throw new HttpError(503, "Could not save subscription checkout");
  }
  return { url: session.url };
}));