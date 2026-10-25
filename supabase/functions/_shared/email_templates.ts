/** Branded, escaped, mobile-friendly transactional email templates. No unauthorised deep links. */
export const APP_URL = "https://www.spicyself.com";

export function escapeEmailHtml(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

type Mail = {kind: string; subject: string; body: string; admin: boolean};
type Presentation = {eyebrow: string; headline: string; intro: string; action: string; destination: string; footnote: string};

export function emailPresentation(mail: Mail): Presentation {
  const {kind, admin} = mail;
  if (admin) return {
    eyebrow: "SPICYSELF · OPERATIONS", headline: mail.subject,
    intro: "An application needs attention in your protected administration workspace.",
    action: "Review in admin portal", destination: "Profile → Administration → Pending",
    footnote: "Only authorised administrators can review applications. Sign-in and MFA are required. Opening this link does not approve anything."
  };
  switch (kind) {
    case "application_received": return {
      eyebrow: "SPICYSELF · FOR BUSINESS", headline: "Your application is in",
      intro: "Thank you for applying to join SpicySelf. Our team will review your business details.",
      action: "View application status", destination: "Profile → Open business",
      footnote: "Your listing is not yet bookable. You can review your application by signing in with the same account."
    };
    case "decision_approved": return {
      eyebrow: "SPICYSELF · FOR BUSINESS", headline: "Welcome to SpicySelf",
      intro: "Your business has been approved. Your dashboard is ready for setup.",
      action: "Open business dashboard", destination: "Profile → Open business → Business settings",
      footnote: "Add services, prices and opening hours before accepting bookings. Business tools require MFA. Your approved public listing may already be visible in local search."
    };
    case "booking_confirmed":
    case "appointment_confirmed":
    case "visit_booked": return {
      eyebrow: "SPICYSELF · YOUR BOOKING", headline: "Your appointment is confirmed",
      intro: "You're booked. Your visit details are below.",
      action: "View my bookings", destination: "My Bookings → Upcoming",
      footnote: "Check your booking details in SpicySelf. Follow your business's cancellation policy and any applicable consumer rights."
    };
    case "queue_joined":
    case "queue_confirmed": return {
      eyebrow: "SPICYSELF · LIVE QUEUE", headline: "You're in the queue",
      intro: "Your place in line has been recorded. Queue times can change.",
      action: "Track my queue", destination: "My Bookings → Upcoming",
      footnote: "Open SpicySelf for the latest queue status. Estimated waits are not guaranteed."
    };
    case "booking_cancelled":
    case "appointment_cancelled":
    case "visit_cancelled": return {
      eyebrow: "SPICYSELF · YOUR BOOKING", headline: "Your booking was cancelled",
      intro: "Your booking status has been updated.",
      action: "View booking history", destination: "My Bookings → Cancelled",
      footnote: "If payment was taken, check your account for any refund status."
    };
    case "booking_reminder":
    case "appointment_reminder": return {
      eyebrow: "SPICYSELF · REMINDER", headline: "Your appointment is coming up",
      intro: "A quick reminder about your upcoming visit.",
      action: "View appointment", destination: "My Bookings → Upcoming",
      footnote: "Please check the appointment time and location in your account."
    };
    case "decision_updated": return {
      eyebrow: "SPICYSELF · FOR BUSINESS", headline: "Your application has been updated",
      intro: "There is an update on your SpicySelf business application.",
      action: "View application", destination: "Profile → Open business",
      footnote: "You can view your current approval status after signing in."
    };
    case "decision_rejected": return {
      eyebrow: "SPICYSELF · FOR BUSINESS", headline: "An update on your application",
      intro: "We have completed our review. Please read the decision and review notes in your account.",
      action: "View review decision", destination: "Profile → Open business",
      footnote: "If you need to clarify any details, contact SpicySelf support. No booking tools have been enabled."
    };
    case "decision_suspended": return {
      eyebrow: "SPICYSELF · FOR BUSINESS", headline: "Your business status has changed",
      intro: "Your business account has been suspended. Review the reason in your workspace.",
      action: "Review business status", destination: "Profile → Open business",
      footnote: "Your public listing and new bookings may be unavailable during suspension."
    };
    default: return {
      eyebrow: "SPICYSELF · NOTIFICATIONS", headline: mail.subject,
      intro: "There's a new update in your SpicySelf account.",
      action: "Open SpicySelf", destination: "Sign in to view the latest details",
      footnote: "For your security, sign in to view account-specific information. Do not share login or authenticator codes."
    };
  }
}

export function appEmailHtml(mail: Mail, url: string = APP_URL): string {
  const link = new URL(url);
  if (link.protocol !== "https:" || link.username || link.password) throw Error("Invalid app URL");
  const p = emailPresentation(mail);
  const safe = (s: string) => escapeEmailHtml(s);
  const message = safe(mail.body).replaceAll("\n", "<br>");
  const href = safe(link.toString());
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SpicySelf</title></head>
<body style="margin:0;padding:0;background:#f5f5f0;font-family:Arial,Helvetica,sans-serif;color:#173b32">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">${safe(p.intro)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f5f0"><tr><td align="center" style="padding:32px 12px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#fff;border:1px solid #e4e9e2;border-radius:16px;overflow:hidden">
<tr><td style="background:#163e35;padding:28px 32px">
<div style="color:#fff;font-size:26px;font-weight:800;letter-spacing:-.5px">SpicySelf<span style="color:#e3d3a5">.</span></div>
<div style="color:#d2e4dc;font-size:11px;letter-spacing:2px;text-transform:uppercase;margin-top:8px">${safe(p.eyebrow)}</div></td></tr>
<tr><td style="padding:36px 32px">
<h1 style="font-size:27px;line-height:1.2;margin:0 0 16px;color:#163e35">${safe(p.headline)}</h1>
<p style="font-size:16px;line-height:1.65;color:#435b52;margin:0 0 18px">${safe(p.intro)}</p>
<div style="background:#f5f7f3;border-left:3px solid #accab6;padding:18px 20px;font-size:15px;line-height:1.6;color:#263c32;margin:0 0 26px">${message}</div>
<table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="border-radius:9px;background:#163e35"><a href="${href}" style="display:inline-block;padding:16px 24px;color:#fff;text-decoration:none;font-size:15px;font-weight:bold">${safe(p.action)}</a></td></tr></table>
<p style="font-size:13px;line-height:1.6;color:#63736b;margin:20px 0 0">After signing in: <strong>${safe(p.destination)}</strong></p>
<p style="font-size:13px;line-height:1.6;color:#63736b;margin:10px 0 0">${safe(p.footnote)}</p></td></tr>
<tr><td style="background:#eef3ed;padding:22px 32px;border-top:1px solid #e4e9e2">
<p style="font-size:13px;margin:0 0 8px;color:#355347"><strong>SpicySelf on your phone</strong></p>
<p style="font-size:13px;line-height:1.6;margin:0;color:#456055">Use the <a href="${href}" style="color:#163e35;font-weight:bold">SpicySelf web app</a> anytime. For quick access, open the website in your phone browser and choose <strong>Add to Home Screen</strong> if supported. Official App Store / Google Play downloads will be linked here once published.</p>
<p style="font-size:12px;line-height:1.6;margin:16px 0 0;color:#63736b">If the button doesn't open, use <a href="${href}" style="color:#163e35">${href}</a>.</p>
<p style="font-size:12px;line-height:1.6;margin:10px 0 0;color:#63736b">This is a service notification from SpicySelf. Never share your password or authenticator code.</p>
</td></tr></table></td></tr></table></body></html>`;
}

export function appEmailText(mail: Mail, url: string = APP_URL): string {
  const p = emailPresentation(mail);
  return [p.headline, "", p.intro, "", mail.body, "", p.action + ": " + url,
    "After signing in: " + p.destination, p.footnote, "",
    "Use SpicySelf on your phone: " + url,
    "Add to Home Screen in your browser if supported. Store downloads aren't published yet."].join("\n");
}
