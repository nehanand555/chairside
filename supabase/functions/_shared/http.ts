import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";

export function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Service configuration missing: ${name}`);
  return value;
}
export function service(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false, autoRefreshToken: false } });
}
export async function authenticated(req: Request) {
  const token = req.headers.get("Authorization");
  if (!token?.startsWith("Bearer ")) throw new HttpError(401, "Please sign in again");
  const client = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { global: { headers: { Authorization: token } }, auth: { persistSession: false } });
  const { data, error } = await client.auth.getUser(token.slice(7));
  if (error || !data.user?.phone_confirmed_at) throw new HttpError(401, "Verify your phone number first");
  return { user: data.user, client };
}
export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
export async function rpc<T = unknown>(client: SupabaseClient, name: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new HttpError(400, error.message);
  return data as T;
}
export async function body(req: Request): Promise<Record<string, unknown>> {
  if (Number(req.headers.get("content-length") ?? 0) > 16384) throw new HttpError(413, "Request too large");
  const raw = await req.text();
  if (raw.length > 16384) throw new HttpError(413, "Request too large");
  try { const data = JSON.parse(raw); if (!data || Array.isArray(data) || typeof data !== "object") throw 0; return data; }
  catch { throw new HttpError(400, "Invalid request"); }
}
export function uuid(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) throw new HttpError(400, "Invalid identifier");
  return value;
}
export function endpoint(handler: (req: Request) => Promise<unknown>) {
  return async (req: Request): Promise<Response> => {
    const origin = req.headers.get("origin");
    const allowed = (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map(x => x.trim()).filter(Boolean);
    const headers = new Headers({ "content-type": "application/json", "cache-control": "no-store", "vary": "Origin", "access-control-allow-headers": "authorization, apikey, content-type, x-client-info", "access-control-allow-methods": "POST, OPTIONS" });
    if (origin && !allowed.includes(origin)) return new Response(JSON.stringify({ error: "Origin not allowed" }), { status: 403, headers });
    if (origin) headers.set("access-control-allow-origin", origin);
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
    if (req.method !== "POST") return new Response(JSON.stringify({ error: "Use POST" }), { status: 405, headers });
    try { return new Response(JSON.stringify(await handler(req)), { headers }); }
    catch (e) {
      // Never send API keys, upstream responses, addresses or stack traces to the client/logs.
      const status = e instanceof HttpError ? e.status : 503;
      const message = e instanceof HttpError ? e.message : "This service is temporarily unavailable. Please try again.";
      return new Response(JSON.stringify({ error: message }), { status, headers });
    }
  };
}
export async function limited(key: string, max: number, seconds: number) {
  if (!await rpc<boolean>(service(), "integration_limit", { p_key: key, p_max: max, p_seconds: seconds })) throw new HttpError(429, "Too many requests. Please try again later.");
}
