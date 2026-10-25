import { env, rpc, service } from "../_shared/http.ts";

// Invoke with x-worker-secret from a trusted scheduler. Never callable with user JWT alone.
Deno.serve(async (req) => {
  if (req.method !== "POST" || !Deno.env.get("WORKER_SECRET") ||
      req.headers.get("x-worker-secret") !== Deno.env.get("WORKER_SECRET")) {
    return new Response("Unauthorized", { status: 401 });
  }
  const sender = Deno.env.get("RESEND_FROM_EMAIL");
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const admin = Deno.env.get("APPLICATION_REVIEW_EMAIL");
  if (!sender || !apiKey || !admin) {
    return Response.json({ error: "email_configuration_required" }, { status: 503 });
  }
  const db = service();
  const tasks = await rpc<Array<{id:string;kind:string;recipient:string;subject:string;body:string;dedupe_key:string}>>(db, "email_claim_batch");
  const totals = { claimed: tasks.length, accepted: 0, retried: 0, failed: 0 };
  for (const task of tasks) {
    const recipient = task.recipient === "admin-routing@spicyself.invalid" ? admin : task.recipient;
    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST", signal: AbortSignal.timeout(15000),
        headers: {"Authorization": "Bearer " + apiKey, "Content-Type": "application/json",
          "Idempotency-Key": task.dedupe_key},
        body: JSON.stringify({from: sender, to: [recipient], subject: task.subject, text: task.body}),
      });
      if (response.ok) {
        const payload = await response.json() as { id?: string };
        if (!payload.id) {
          // Ambiguous provider acceptance: do not retry blindly.
          await rpc(db, "email_mark_result", {p_id:task.id,p_state:"failed",p_error:"missing_provider_id"});
          totals.failed++; continue;
        }
        await rpc(db, "email_mark_result", {p_id:task.id,p_state:"accepted",p_provider:payload.id});
        totals.accepted++;
      } else {
        const retryable = response.status === 429 || response.status >= 500;
        await rpc(db, "email_mark_result", {p_id:task.id,p_state:retryable?"retry":"failed",p_error:"http_"+response.status});
        if (retryable) totals.retried++; else totals.failed++;
      }
    } catch {
      // Network timeouts may occur after acceptance. Mark for manual reconciliation.
      await rpc(db, "email_mark_result", {p_id:task.id,p_state:"failed",p_error:"ambiguous_network"});
      totals.failed++;
    }
  }
  return Response.json(totals);
});
