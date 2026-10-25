export function messageFor(message: { kind: string; status: string; business: string; starts_at: string }): string | null {
  const name = message.business.replace(/[\r\n]/g, " ").slice(0, 60);
  if (message.kind === "cancelled") return message.status === "cancelled" ? `spicyself: Your visit at ${name} was cancelled. View My Bookings for details and refund status.` : null;
  if (!["waiting", "booked"].includes(message.status)) return null;
  if (message.kind === "next") return message.status === "waiting" ? `spicyself: Your turn at ${name} is getting closer. Check My Bookings for the latest estimate. Times may change.` : null;
  const time = new Intl.DateTimeFormat("en-NZ", { timeZone: "Pacific/Auckland", dateStyle: "short", timeStyle: "short" }).format(new Date(message.starts_at));
  if (message.kind === "reminder") return `spicyself reminder: ${name}, ${time} NZ time. Check My Bookings for details or to cancel.`;
  if (message.kind === "confirmation") return `spicyself: Your ${message.status === "waiting" ? "queue place" : "appointment"} at ${name} is confirmed. ${message.status === "waiting" ? "Estimated " : ""}${time} NZ time. See My Bookings for updates.`;
  return null;
}
