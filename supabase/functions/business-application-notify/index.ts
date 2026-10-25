import { authenticated, body, endpoint, rpc, uuid } from "../_shared/http.ts";

// Application and recipient notifications are written transactionally by DB triggers.
// This endpoint checks ownership and returns queued state; the email worker delivers.
Deno.serve(endpoint(async (req) => {
  const {client} = await authenticated(req);
  const input = await body(req);
  const id = uuid(input.business_id);
  const application = await rpc<Record<string,string>|null>(client,"claim_business_application_notification",{p_business:id});
  if (!application) return {queued_for_admin:true,email_sent:false,already_processed:true};
  return {queued_for_admin:true,email_sent:false,email_queued:true};
}));
