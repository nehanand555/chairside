import { authenticated, body, endpoint, env, HttpError, limited, rpc, service, uuid } from "../_shared/http.ts";
import { stripe, Stripe } from "../_shared/stripe.ts";

Deno.serve(endpoint(async req => {
  const { user, client } = await authenticated(req);
  await limited(`payments:${user.id}`, 20, 600);
  const data = await body(req), db = service(), api = stripe();
  const returnUrl = new URL(env("APP_URL"));
  if (returnUrl.protocol !== "https:") throw new HttpError(503, "Payments need a secure application URL");
  // All redirect URLs are configured server-side, never supplied by a caller.
  if (data.action === "checkout") {
    const checkout = await rpc<{ id: string; url: string | null; amount: number; expires_at: string; account: string; service_name: string }>(db, "integration_checkout", { p_user: user.id, p_visit: uuid(data.visit_id) });
    if (checkout.url) return { url: checkout.url };
    const methods: Stripe.Checkout.SessionCreateParams.PaymentMethodType[] = ["card"];
    if (Deno.env.get("ENABLE_AFTERPAY") === "true") methods.push("afterpay_clearpay");
    const session = await api.checkout.sessions.create({
      mode: "payment", payment_method_types: methods,
      line_items: [{ price_data: { currency: "nzd", unit_amount: checkout.amount, product_data: { name: checkout.service_name } }, quantity: 1 }],
      payment_intent_data: { transfer_data: { destination: checkout.account }, metadata: { chairside_visit: String(data.visit_id) } },
      metadata: { chairside_session: checkout.id },
      success_url: returnUrl.toString(), cancel_url: returnUrl.toString(),
      expires_at: Math.floor(new Date(checkout.expires_at).getTime() / 1000),
    }, { idempotencyKey: `chairside-checkout-${checkout.id}` });
    await rpc(db, "integration_checkout_saved", { p_id: checkout.id, p_stripe: session.id, p_url: session.url });
    return { url: session.url };
  }
  if (!["connect", "sync", "dashboard"].includes(String(data.action))) throw new HttpError(400, "Unknown payment action");
  const business = uuid(data.business_id);
  // Uses the caller's JWT: verifies actual ownership/admin membership AND aal2 in PostgreSQL.
  const listing = await rpc<{ name: string; status: string }>(client, "operator_business", { p_business: business });
  if (listing.status !== "approved") throw new HttpError(400, "Your business must be approved before enabling payments");
  let account = await rpc<{ stripe_account: string | null }>(db, "integration_account", { p_business: business });
  if (!account.stripe_account) {
    if (data.action !== "connect") throw new HttpError(400, "Set up Stripe first");
    const created = await api.accounts.create({ type: "express", country: "NZ", capabilities: { card_payments: { requested: true }, transfers: { requested: true } }, business_profile: { name: listing.name }, metadata: { chairside_business: business } }, { idempotencyKey: `chairside-account-${business}` });
    account = await rpc(db, "integration_account", { p_business: business, p_account: created.id });
  }
  const id = account.stripe_account!;
  if (data.action === "sync") {
    const result = await api.accounts.retrieve(id);
    await rpc(db, "integration_account", { p_business: business, p_enabled: result.charges_enabled && result.payouts_enabled });
    return { enabled: result.charges_enabled && result.payouts_enabled };
  }
  if (data.action === "dashboard") return { url: (await api.accounts.createLoginLink(id)).url };
  const link = await api.accountLinks.create({ account: id, type: "account_onboarding", refresh_url: returnUrl.toString(), return_url: returnUrl.toString() });
  return { url: link.url };
}));
