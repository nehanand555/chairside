import { rpc, service } from "../_shared/http.ts";

// Admin links navigate to the public app; authorisation and MFA remain enforced in-app.
function adminPortalUrl(): string {
  const value = Deno.env.get("SPICYSELF_ADMIN_URL") ?? "https://spicyself.com";
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password) throw new Error("Invalid admin portal URL");
  return url.toString();
}

function escapeHtml(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function adminNotificationHtml(subject: string, message: string, url: string): string {
  const safeText = escapeHtml(message).replaceAll("\n", "<br>");
  const safeUrl = escapeHtml(url);
  return `<!doctype html><html lang="en"><body style="margin:0;background:#f8f7f2;color:#163e35;font-family:Arial,sans-serif">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:32px 16px">
  <table role="presentation" width="100%" style="max-width:600px;background:#fff;border-radius:16px"><tr><td style="padding:32px">
  <p style="font-size:14px;font-weight:bold;letter-spacing:1px">SPICYSELF ADMIN</p>
  <h1 style="font-size:24px">${escapeHtml(subject)}</h1>
  <p style="line-height:1.7;color:#354e46">${safeText}</p>
  <p style="margin:30px 0"><a href="${safeUrl}" style="background:#163e35;color:#fff;text-decoration:none;border-radius:8px;padding:14px 22px;display:inline-block;font-weight:bold">Open SpicySelf Admin Portal</a></p>
  <p style="font-size:13px;color:#52635c">Sign in with your admin account, then open Profile → Administration → Pending. MFA may be required. This email never approves an application.</p>
  <p style="font-size:12px;color:#52635c">If the button does not open, visit <a href="${safeUrl}">${safeUrl}</a>.</p>
  </td></tr></table></td></tr></table></body></html>`;
}


// Invoke with x-worker-secret from a trusted scheduler. Never callable with user JWT alone.
Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const workerSecret = Deno.env.get("WORKER_SECRET");
  const providedWorkerSecret = req.headers.get("x-worker-secret");
  const githubAuthenticated = !!workerSecret && !!providedWorkerSecret &&
    providedWorkerSecret === workerSecret;
  let cronAuthenticated = false;
  if (!githubAuthenticated && req.headers.get("x-cron-token")) {
    try {
      cronAuthenticated = await rpc<boolean>(service(), "email_validate_cron_token", {
        p_token: req.headers.get("x-cron-token"),
      });
    } catch {
      cronAuthenticated = false;
    }
  }
  if (!githubAuthenticated && !cronAuthenticated) {
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
    const isAdminAlert = task.recipient === "admin-routing@spicyself.invalid";
    const recipient = isAdminAlert ? admin : task.recipient;
    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST", signal: AbortSignal.timeout(15000),
        headers: {"Authorization": "Bearer " + apiKey, "Content-Type": "application/json",
          "Idempotency-Key": task.id},
        body: JSON.stringify({from: sender, to: [recipient], subject: task.subject,
          text: isAdminAlert ? task.body + "\\n\\nReview: " + adminPortalUrl() + "\\nSign in, then Profile → Administration → Pending." : task.body,
          ...(isAdminAlert ? {html: adminNotificationHtml(task.subject, task.body, adminPortalUrl())} : {})}),
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
