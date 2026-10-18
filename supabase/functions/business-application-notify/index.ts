import { authenticated, body, endpoint, env, HttpError, rpc, uuid } from "../_shared/http.ts";

// Optional email delivery: set RESEND_API_KEY, RESEND_FROM_EMAIL and
// APPLICATION_REVIEW_EMAIL in Supabase Edge Function secrets.
Deno.serve(endpoint(async (req) => {
  const { client } = await authenticated(req);
  const input = await body(req);
  const businessId = uuid(input.business_id);
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("RESEND_FROM_EMAIL");
  const to = Deno.env.get("APPLICATION_REVIEW_EMAIL");
  if (!apiKey || !from || !to) {
    return { queued_for_admin: true, email_sent: false, configuration_required: true };
  }
  const application = await rpc<Record<string, string> | null>(
    client, "claim_business_application_notification", { p_business: businessId },
  );
  if (!application) return { queued_for_admin: true, email_sent: false, already_processed: true };
  const message = [
    "A new SpicySelf business application needs review.",
    "Business: " + application.business_name,
    "Registration number: " + application.registration_number,
    "Contact: " + application.contact_name,
    "Email: " + application.contact_email,
    "Phone: " + application.contact_phone,
    "Type: " + application.business_kind,
    "Suburb: " + application.suburb,
    "Application ID: " + application.business_id,
    "Review and verify in the SpicySelf Admin tab. No business has been automatically approved.",
  ].join("\n");
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    signal: AbortSignal.timeout(10000),
    headers: { Authorization: "Bearer " + apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      from,
      to: [to],
      subject: "New SpicySelf business application: " + application.business_name,
      text: message,
    }),
  });
  if (!response.ok) throw new HttpError(503,
    "Application saved, but review email could not be sent. It is available in the admin queue.");
  return { queued_for_admin: true, email_sent: true };
}));
