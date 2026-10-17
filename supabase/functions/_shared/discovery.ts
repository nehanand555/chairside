export type Place = {
  id?: string; displayName?: { text?: string }; formattedAddress?: string;
  location?: { latitude?: number; longitude?: number }; googleMapsUri?: string;
  businessStatus?: string; attributions?: { provider?: string; providerUri?: string }[];
};
export function normalizePlace(p: Place) {
  if (!p.id || !p.location || p.businessStatus === "CLOSED_PERMANENTLY" || typeof p.location.latitude !== "number" || typeof p.location.longitude !== "number") return null;
  return { place_id: p.id, name: p.displayName?.text ?? "Hair professional", address: p.formattedAddress ?? "", lat: p.location.latitude, lng: p.location.longitude, maps_url: p.googleMapsUri ?? "", attributions: p.attributions ?? [], source: "google" };
}
export function validateArea(data: Record<string, unknown>) {
  const lat = Number(data.lat), lng = Number(data.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -48 || lat > -33 || lng < 165 || lng > 180) throw new Error("Choose a location in New Zealand");
  const query = typeof data.query === "string" ? data.query.trim() : "";
  if (query.length > 100) throw new Error("Search must be 100 characters or fewer");
  return { lat, lng, query };
}

/** Build Google requests server-side; keep NZ postcode searches independent of GPS. */
export function placesRequest(area: { lat: number; lng: number; query: string }) {
  if (area.query) return {
    method: "searchText",
    body: { textQuery: `barbers and hairdressers in ${area.query}, New Zealand`, regionCode: "NZ", pageSize: 20 },
  };
  return {
    method: "searchNearby",
    body: { includedTypes: ["barber_shop", "hair_salon"], maxResultCount: 20,
      locationRestriction: { circle: { center: { latitude: area.lat, longitude: area.lng }, radius: 15000 } } },
  };
}
