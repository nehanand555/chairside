import { authenticated, body, endpoint, env, HttpError, limited } from "../_shared/http.ts";

/** NZ-only Places Autocomplete + Details. The Google server key never reaches Flutter. */
Deno.serve(endpoint(async (req) => {
  const { user } = await authenticated(req);
  const input = await body(req);
  const action = input.action;
  const token = typeof input.session_token === "string" ? input.session_token : "";
  if (!/^[A-Za-z0-9_-]{12,36}$/.test(token)) throw new HttpError(400, "Invalid address search session");
  await limited("business-address:" + user.id, 100, 3600);
  const key = env("GOOGLE_PLACES_KEY");
  if (action === "suggest") {
    const query = typeof input.query === "string" ? input.query.trim() : "";
    if (query.length < 3 || query.length > 180) throw new HttpError(400, "Enter at least three address characters");
    const response = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
      method: "POST",
      signal: AbortSignal.timeout(8000),
      headers: {"Content-Type": "application/json", "X-Goog-Api-Key": key},
      body: JSON.stringify({input: query, sessionToken: token, includedRegionCodes: ["nz"],
        regionCode: "nz", languageCode: "en", includeQueryPredictions: false}),
    });
    if (!response.ok) throw new HttpError(503, "Address suggestions are temporarily unavailable");
    const result = await response.json();
    return {suggestions: (result.suggestions ?? []).map((s: Record<string, any>) => s.placePrediction)
      .filter((p: Record<string, any> | undefined) => p?.placeId && p.text?.text)
      .slice(0, 6).map((p: Record<string, any>) => ({
        place_id: p.placeId, description: p.text.text,
      }))};
  }
  if (action === "select") {
    const id = typeof input.place_id === "string" ? input.place_id : "";
    if (!/^[A-Za-z0-9_-]{6,240}$/.test(id)) throw new HttpError(400, "Choose an address suggestion");
    const response = await fetch(
      "https://places.googleapis.com/v1/places/" + encodeURIComponent(id) +
      "?sessionToken=" + encodeURIComponent(token), {
        method: "GET", signal: AbortSignal.timeout(8000),
        headers: {"X-Goog-Api-Key": key,
          "X-Goog-FieldMask": "id,formattedAddress,location,addressComponents"},
      });
    if (!response.ok) throw new HttpError(503, "Could not confirm this address. Try again");
    const place = await response.json();
    const latitude = place.location?.latitude, longitude = place.location?.longitude;
    const components = place.addressComponents ?? [];
    const country = components.find((c: any) => c.types?.includes("country"))?.shortText;
    if (country !== "NZ" || typeof latitude !== "number" || typeof longitude !== "number" ||
      latitude < -48 || latitude > -33 || longitude < 165 || longitude > 180) {
      throw new HttpError(400, "Select an address in New Zealand");
    }
    const areaTypes = ["sublocality_level_1", "locality", "postal_town", "administrative_area_level_2"];
    const suburb = areaTypes.map(type => components.find((c: any) => c.types?.includes(type))?.longText)
      .find(Boolean) || "New Zealand";
    return {address: place.formattedAddress, suburb, lat: latitude, lng: longitude,
      place_id: place.id};
  }
  throw new HttpError(400, "Unknown address operation");
}));