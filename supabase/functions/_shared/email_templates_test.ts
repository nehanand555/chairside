import { appEmailHtml, appEmailText, emailPresentation, APP_URL } from "./email_templates.ts";

Deno.test("all email roles have safe, actionable, branded HTML and plain text", () => {
  const kinds = ["application_received","application_review","application_updated",
    "decision_approved","decision_rejected","decision_suspended",
    "booking_confirmed","queue_joined","booking_cancelled","booking_reminder"];
  for (const kind of kinds) {
    const m = {kind, subject: "Notice", body: "Hello\nDetails & updates", admin: kind === "application_review" || kind === "application_updated"};
    const html = appEmailHtml(m);
    const text = appEmailText(m);
    if (!html.includes("spicyself") || !html.includes(APP_URL) ||
        !html.includes("Add to Home Screen") || !html.includes("<a href=") ||
        !text.includes(APP_URL) || !emailPresentation(m).action) {
      throw new Error("Incomplete email for " + kind);
    }
  }
});
Deno.test("user-supplied text is escaped and no unsafe HTML is inserted", () => {
  const html=appEmailHtml({kind:"decision_approved",admin:false,subject:"<img src=x>",
    body:'<script>alert("x")</script>\nTest & confirm'});
  if (html.includes("<script>") || html.includes("<img src=x>") ||
      !html.includes("&lt;script&gt;") || !html.includes("&amp;")) {
    throw Error("Unsafe HTML");
  }
});
Deno.test("invalid redirect destinations are rejected", () => {
  for (const url of ["javascript:alert(1)","http://example.com","https://user:password@example.com"]) {
    let rejected=false;
    try {appEmailHtml({kind:"application_received",admin:false,subject:"Test",body:"Test"},url);}
    catch {rejected=true;}
    if(!rejected)throw Error("Unsafe email URL accepted");
  }
});

Deno.test("legacy queued brand text and headings render in lowercase", () => {
  const mail = {kind:"application_review",admin:true,subject:"SpicySelf review",body:"Thanks for applying to SpicySelf"};
  for (const output of [appEmailHtml(mail), appEmailText(mail)]) {
    if (/SpicySelf|SPICYSELF/.test(output)) throw Error("Mixed-case branding remains");
    if (!output.includes("https://www.spicyself.com")) throw Error("Missing official portal URL");
  }
});
