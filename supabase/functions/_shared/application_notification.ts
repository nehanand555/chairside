export type ReviewEmail = {
  apiKey: string; from: string; to: string; businessId: string;
  businessName: string; text: string;
};

/** Provider acceptance is independent of application persistence and inbox delivery. */
export async function deliverReviewEmail(email: ReviewEmail, request: typeof fetch = fetch) {
  let response: Response;
  try {
    response = await request("https://api.resend.com/emails", {
      method: "POST", signal: AbortSignal.timeout(10000),
      headers: { Authorization: "Bearer " + email.apiKey, "Content-Type": "application/json",
        "Idempotency-Key": `business-application/${email.businessId}` },
      body: JSON.stringify({from: email.from, to: [email.to],
        subject: "New SpicySelf business application: " + email.businessName, text: email.text}),
    });
  } catch {
    throw new Error("Application saved. The review email service could not be reached; retry later.");
  }
  if (!response.ok) throw new Error(response.status === 429
    ? "Application saved. The email provider is rate limiting requests; retry the review notification later."
    : "Application saved, but Resend rejected the review email. The platform must check its verified sender, credentials and allowed recipient before retrying.");
}
