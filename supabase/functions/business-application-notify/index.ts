import { authenticated, body, endpoint, rpc, uuid } from "../_shared/http.ts";

// Notifications are created transactionally by database triggers.
Deno.serve(endpoint(async (req) => {
  const {client} = await authenticated(req);
  const input = await body(req);
  const id = uuid(input.business_id);
  const result = await rpc<{state:string}>(client,"my_application_email_state",{p_business:id});
  if (result.state === "missing") {
    return {queued_for_admin:false,email_sent:false,email_queued:false,configuration_required:true};
  }
  if (result.state === "accepted" || result.state === "delivered") {
    return {queued_for_admin:true,email_sent:false,already_processed:true};
  }
  if (["failed","dead","bounced"].includes(result.state)) {
    return {queued_for_admin:true,email_sent:false,delivery_failed:true};
  }
  return {queued_for_admin:true,email_sent:false,email_queued:true};
}));
