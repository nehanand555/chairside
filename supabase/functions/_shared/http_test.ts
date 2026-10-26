import { authenticated, endpoint } from "./http.ts";

Deno.test("official domains and configured staging pass preflight without bypassing authentication", async () => {
  const previous = Deno.env.get("ALLOWED_ORIGINS");
  Deno.env.set("ALLOWED_ORIGINS", "https://chairside-staging.pages.dev");
  try {
    const handle = endpoint(async req => { await authenticated(req); return {ok:true}; });
    for (const origin of ["https://www.spicyself.com", "https://spicyself.com", "https://chairside-staging.pages.dev", "https://feature-home.chairside-staging.pages.dev"]) {
      const preflight = await handle(new Request("https://edge.invalid", {method:"OPTIONS",headers:{origin}}));
      if (preflight.status !== 204 || preflight.headers.get("access-control-allow-origin") !== origin) throw Error("Valid origin rejected");
      const unauthenticated = await handle(new Request("https://edge.invalid", {method:"POST",headers:{origin},body:"{}"}));
      if (unauthenticated.status !== 401) throw Error("CORS bypassed authentication");
    }
    for (const origin of ["https://attacker.invalid", "https://www.spicyself.com.attacker.invalid", "http://www.spicyself.com"]) {
      const response = await handle(new Request("https://edge.invalid", {method:"OPTIONS",headers:{origin}}));
      if (response.status !== 403 || response.headers.has("access-control-allow-origin")) throw Error("Untrusted origin allowed");
    }
  } finally {
    if (previous === undefined) Deno.env.delete("ALLOWED_ORIGINS");
    else Deno.env.set("ALLOWED_ORIGINS", previous);
  }
});
