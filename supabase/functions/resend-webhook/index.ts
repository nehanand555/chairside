import { rpc, service } from "../_shared/http.ts";

// Resend webhooks use Svix signatures: id.timestamp.raw_body, HMAC-SHA256.
// Rejected if the signed timestamp is stale (> 5 minutes).
Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const secret = Deno.env.get("RESEND_WEBHOOK_SECRET");
  if (!secret) return new Response("Webhook not configured", { status: 503 });
  const id = req.headers.get("svix-id") ?? "";
  const stamp = req.headers.get("svix-timestamp") ?? "";
  const signatures = req.headers.get("svix-signature") ?? "";
  const ts = Number(stamp);
  if (!id || !Number.isFinite(ts) || Math.abs(Date.now() / 1000 - ts) > 300)
    return new Response("Invalid signature", { status: 401 });
  const raw = await req.text();
  const keyRaw = secret.startsWith("whsec_") ? secret.slice(6) : secret;
  let bytes: Uint8Array;
  try { bytes = Uint8Array.from(atob(keyRaw), c => c.charCodeAt(0)); }
  catch { return new Response("Webhook configuration invalid", { status: 503 }); }
  const keyBytes = new Uint8Array(bytes.length);
  keyBytes.set(bytes);
  const key = await crypto.subtle.importKey("raw", keyBytes.buffer, {name:"HMAC",hash:"SHA-256"}, false, ["verify"]);
  let authentic = false;
  for (const part of signatures.split(" ")) {
    if (!part.startsWith("v1,")) continue;
    try {
      const sig = Uint8Array.from(atob(part.slice(3)), c => c.charCodeAt(0));
      const signatureBytes = new Uint8Array(sig.length);
      signatureBytes.set(sig);
      if (await crypto.subtle.verify("HMAC",key,signatureBytes.buffer,new TextEncoder().encode(id+"."+stamp+"."+raw))) authentic = true;
    } catch { /* malformed signature */ }
  }
  if (!authentic) return new Response("Invalid signature", { status: 401 });
  let payload: {type?:string;data?:{email_id?:string}};
  try { payload = JSON.parse(raw); }
  catch { return new Response("Invalid JSON", { status: 400 }); }
  const map: Record<string,string> = {
    "email.delivered":"delivered", "email.bounced":"bounced", "email.failed":"failed",
    "email.complained":"failed",
  };
  const event = map[payload.type ?? ""];
  if (event && payload.data?.email_id) {
    await rpc(service(),"email_mark_delivery",{p_provider:payload.data.email_id,p_event:event});
  }
  return Response.json({ok:true});
});
