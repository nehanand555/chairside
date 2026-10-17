import { env, rpc, service } from "../_shared/http.ts";
import { processRefunds } from "../_shared/stripe.ts";
import { messageFor } from "../_shared/messages.ts";

Deno.serve(async req => {
  if (req.method !== "POST" || req.headers.get("x-worker-secret") !== env("WORKER_SECRET")) return new Response("Unauthorized", { status: 401 });
  const db = service();
  await rpc(db, "integration_tick");
  let refunds = 0;
  if (Deno.env.get("STRIPE_SECRET_KEY")) refunds = await processRefunds();
  // Leave pending messages untouched until the SMS provider is configured.
  if (!Deno.env.get("TWILIO_ACCOUNT_SID") || !Deno.env.get("TWILIO_AUTH_TOKEN") || !Deno.env.get("TWILIO_FROM")) return Response.json({ refunds, sms: "not configured" });
  const messages = await rpc<{ id: string; kind: string; phone: string | null; consent: boolean; status: string; business: string; starts_at: string }[]>(db, "integration_claim_messages");
  let sent = 0;
  for (const message of messages) {
    const text = messageFor(message);
    if (!text || !message.phone || !message.consent) { await rpc(db, "integration_message_done", { p_id: message.id, p_state: "skipped" }); continue; }
    try {
      const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${env("TWILIO_ACCOUNT_SID")}/Messages.json`, {
        method: "POST", signal: AbortSignal.timeout(15000),
        headers: { "Authorization": `Basic ${btoa(env("TWILIO_ACCOUNT_SID") + ":" + env("TWILIO_AUTH_TOKEN"))}`, "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ To: message.phone, From: env("TWILIO_FROM"), Body: text }),
      });
      if (!response.ok) throw new Error("SMS provider rejected the request");
      const result = await response.json();
      // 'sent' means accepted by Twilio, not confirmed delivery to a handset.
      await rpc(db, "integration_message_done", { p_id: message.id, p_state: "sent", p_provider: result.sid }); sent++;
    } catch { await rpc(db, "integration_message_done", { p_id: message.id, p_state: "failed", p_error: "SMS was not confirmed; review provider logs before resending" }); }
  }
  return Response.json({ accepted: sent, refunds });
});
