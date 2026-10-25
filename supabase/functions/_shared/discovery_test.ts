import { normalizePlace, placesRequest, validateArea } from "./discovery.ts";
import { messageFor } from "./messages.ts";
function equal(actual: unknown, expected: unknown) { if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`); }
Deno.test("public map results have no invented booking fields", () => {
  const place = normalizePlace({ id: "place", displayName: { text: "A barber" }, location: { latitude: -36.8, longitude: 174.7 } });
  equal(place?.name, "A barber"); equal("queue_open" in place!, false); equal(place?.website_url, ""); equal("price" in place!, false);
  const linked = normalizePlace({ id: "linked", location: { latitude: -41.3, longitude: 174.8 }, websiteUri: "https://barber.example/book" });
  equal(linked?.website_url, "https://barber.example/book");
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

Deno.test("postcode and suburb searches reach Google without requiring a local member", () => {
  const postcode = placesRequest(validateArea({ lat: -36.85, lng: 174.76, query: " 5014 " }));
  equal(postcode.method, "searchText");
  equal(postcode.body.textQuery, "barbers and hairdressers in 5014, New Zealand");
  equal(postcode.body.regionCode, "NZ");
  equal(placesRequest(validateArea({ lat: -41.28, lng: 174.77, query: "Lower Hutt" })).method, "searchText");
});
Deno.test("nearby search uses the supplied GPS center and hair business types", () => {
  const nearby = placesRequest({ lat: -41.28, lng: 174.77, query: "" });
  equal(nearby.method, "searchNearby");
  equal(nearby.body.locationRestriction?.circle.center, { latitude: -41.28, longitude: 174.77 });
  equal(nearby.body.includedTypes, ["barber_shop", "hair_salon"]);
});

Deno.test("booking SMS uses current lowercase brand and customer navigation", () => {
  for (const [kind,status] of [["confirmation","booked"],["reminder","booked"],["next","waiting"],["cancelled","cancelled"]]) {
    const text = messageFor({kind,status,business:"Test studio",starts_at:"2026-10-18T00:00:00Z"});
    if (!text?.startsWith("spicyself") || !text.includes("My Bookings") || /Chairside|SpicySelf/.test(text)) throw Error("Outdated SMS branding");
  }
});
