import { authenticated, endpoint, HttpError, limited, rpc, service } from "../_shared/http.ts";

Deno.serve(endpoint(async req => {
  const { user } = await authenticated(req);
  await limited(`delete:${user.id}`, 3, 3600);
  // Require a fresh sign-in to delete an account, not a long-lived stolen session.
  const last = new Date(user.last_sign_in_at ?? 0).getTime();
  if (Date.now() - last > 10 * 60 * 1000) throw new HttpError(403, "Please sign out and sign in again before deleting your account");
  const db = service();
  await rpc(db, "integration_delete_user", { p_user: user.id });
  const { data: businesses } = await db.from("businesses").select("id").eq("owner_id", user.id);
  for (const business of businesses ?? []) {
    const bucket = db.storage.from("portfolios");
    // Storage removals are idempotent. Paginate until no objects remain.
    for (let page = 0; page < 100; page++) {
      const { data, error } = await bucket.list(business.id, { limit: 100 });
      if (error) throw error;
      if (!data?.length) break;
      const { error: removeError } = await bucket.remove(data.map(file => `${business.id}/${file.name}`));
      if (removeError) throw removeError;
    }
  }
  const { error } = await db.auth.admin.deleteUser(user.id, true);
  if (error) throw error;
  return { deleted: true };
}));
