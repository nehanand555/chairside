export type ReviewEmail = {
  apiKey: string; from: string; to: string; businessId: string;
  businessName: string; text: string;
};


// Escape application-controlled fields before including them in HTML email.
export function escapeEmailHtml(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function reviewEmailHtml(email: Pick<ReviewEmail, "businessName" | "businessId">): string {
  const business = escapeEmailHtml(email.businessName);
  const id = escapeEmailHtml(email.businessId);
  // A link opens the application, never authorises approval. The admin
  // console still requires a signed-in admin and MFA.
  const url = (Deno.env.get("SPICYSELF_ADMIN_URL") ?? "https://chairside-staging.pages.dev").replace(/\/$/, "");
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"></head>
<body style="margin:0;background:#f8f7f0;font-family:Arial,sans-serif;color:#163e35">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:36px 16px">
<table role="presentation" width="100%" style="max-width:560px;background:white;border-radius:18px" cellpadding="0" cellspacing="0">
<tr><td style="padding:32px">
<p style="font-size:14px;font-weight:bold;letter-spacing:1px">SPICYSELF FOR BUSINESS</p>
<h1 style="font-size:26px;margin:16px 0">New application to review</h1>
<p style="font-size:16px;line-height:1.6">A business has applied to join SpicySelf. Verify its details before approving.</p>
<p style="font-size:18px"><strong>${business}</strong></p>
<p style="font-size:13px;color:#52635c">Application ID: ${id}</p>
<p style="margin:28px 0"><a href="${url}" style="background:#163e35;color:white;text-decoration:none;padding:14px 22px;border-radius:9px;display:inline-block">Open SpicySelf admin portal</a></p>
<p style="font-size:13px;color:#52635c;line-height:1.6">Sign in with an authorised admin account and complete MFA. Open Admin → Pending to review. This email does not approve the business.</p>
</td></tr></table></td></tr></table></body></html>`;
}

/** Provider acceptance is independent of application persistence and inbox delivery. */
export async function deliverReviewEmail(email: ReviewEmail, request: typeof fetch = fetch) {
  let response: Response;
  try {
    response = await request("https://api.resend.com/emails", {
      method: "POST", signal: AbortSignal.timeout(10000),
      headers: { Authorization: "Bearer " + email.apiKey, "Content-Type": "application/json",
        "Idempotency-Key": `business-application/${email.businessId}` },
      body: JSON.stringify({from: email.from, to: [email.to],
        subject: "New SpicySelf business application: " + email.businessName, text: email.text, html: reviewEmailHtml(email)}),
    });
  } catch {
    throw new Error("Application saved. The review email service could not be reached; retry later.");
  }
  if (!response.ok) throw new Error(response.status === 429
    ? "Application saved. The email provider is rate limiting requests; retry the review notification later."
    : "Application saved, but Resend rejected the review email. The platform must check its verified sender, credentials and allowed recipient before retrying.");
}
