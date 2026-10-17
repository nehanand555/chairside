import { normalizePlace, validateArea } from "./discovery.ts";
import { messageFor } from "./messages.ts";
function equal(actual: unknown, expected: unknown) { if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`); }
Deno.test("public map results have no invented booking fields", () => {
  const place = normalizePlace({ id: "place", displayName: { text: "A barber" }, location: { latitude: -36.8, longitude: 174.7 } });
  equal(place?.name, "A barber"); equal("queue_open" in place!, false); equal("price" in place!, false);
  equal(normalizePlace({ id: "closed", businessStatus: "CLOSED_PERMANENTLY", location: {} }), null);
});
Deno.test("discovery refuses coordinates outside New Zealand", () => {
  let rejected = false; try { validateArea({ lat: 100, lng: 0 }); } catch { rejected = true; } equal(rejected, true);
  equal(validateArea({ lat: -41.28, lng: 174.77, query: " Wellington " }).query, "Wellington");
});
Deno.test("no stale reminder after cancellation or completion", () => {
  equal(messageFor({ kind: "reminder", status: "cancelled", business: "Shop", starts_at: "2026-10-18T00:00:00Z" }), null);
  equal(messageFor({ kind: "next", status: "completed", business: "Shop", starts_at: "2026-10-18T00:00:00Z" }), null);
  equal(messageFor({ kind: "next", status: "waiting", business: "Shop", starts_at: "2026-10-18T00:00:00Z" })?.includes("estimate"), true);
});
