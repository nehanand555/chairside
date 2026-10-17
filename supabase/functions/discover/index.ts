import { body, endpoint, env, HttpError, limited, rpc, service } from "../_shared/http.ts";
import { normalizePlace, Place, validateArea } from "../_shared/discovery.ts";

Deno.serve(endpoint(async req => {
  let area;
  try { area = validateArea(await body(req)); } catch (e) { throw new HttpError(400, (e as Error).message); }
  // Trust the platform-provided forwarding header, hash it rather than persisting raw IPs.
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(env("RATE_LIMIT_SALT") + ip));
  const hash = Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2, "0")).join("");
  await limited(`discover:${hash}`, 30, 600);
  await limited("discover:global", Number(Deno.env.get("DISCOVERY_DAILY_LIMIT") ?? 1000), 86400);
  let { lat, lng } = area;
  let places: ReturnType<typeof normalizePlace>[] = [];
  let warning: string | null = null;
  const key = Deno.env.get("GOOGLE_PLACES_KEY");
  if (key) {
    const text = area.query.length > 0;
    const request = text ? { textQuery: `barbers and hairdressers in ${area.query}, New Zealand`, regionCode: "NZ", pageSize: 20 } : {
      includedTypes: ["barber_shop", "hair_salon"], maxResultCount: 20,
      locationRestriction: { circle: { center: { latitude: lat, longitude: lng }, radius: 15000 } },
    };
    try {
      const response = await fetch(`https://places.googleapis.com/v1/places:${text ? "searchText" : "searchNearby"}`, {
        method: "POST", signal: AbortSignal.timeout(10000),
        headers: { "content-type": "application/json", "X-Goog-Api-Key": key, "X-Goog-FieldMask": "places.id,places.displayName,places.formattedAddress,places.location,places.googleMapsUri,places.businessStatus,places.attributions" },
        body: JSON.stringify(request),
      });
      if (!response.ok) throw new Error("Places unavailable");
      const json = await response.json();
      places = (json.places ?? []).map((p: Place) => normalizePlace(p)).filter((p: ReturnType<typeof normalizePlace>) => p && p.lat >= -48 && p.lat <= -33 && p.lng >= 165 && p.lng <= 180);
      if (text && places[0]) { lat = places[0].lat; lng = places[0].lng; }
      if (text && !places.length) warning = "No public listings found for that area. Try a nearby town.";
    } catch { warning = "Public map listings are temporarily unavailable. Chairside businesses are still shown."; }
  } else warning = "Public map listings are not activated yet. Showing Chairside businesses.";
  if (area.query && !key) throw new HttpError(503, "Suburb search needs the map service to be activated. Use the map or your location for now.");
  const businesses = await rpc<Record<string, unknown>[]>(service(), "discover_businesses", { p_lat: lat, p_lng: lng, p_radius_km: 25 });
  const ids = new Set(businesses.map(b => b.place_id));
  return { center: { lat, lng }, businesses, places: places.filter(p => p && !ids.has(p.place_id)), warning };
}));
