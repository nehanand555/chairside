-- Run with an authorised administrative connection, never from a public client.
-- Read-only: no grants, reviews, emails, secrets or migration-history changes.
begin read only;
select case lower(u.email)
 when 'spicynetwork75@gmail.com' then 'authorised_admin'
 when 'nehanikitanand@gmail.com' then 'reported_other_account'
 else 'other_admin_member' end as identity,
 u.email_confirmed_at is not null as verified,
 u.deleted_at is not null as deleted,
 exists(select 1 from private.blocked_users b where b.user_id=u.id) as blocked
from private.admins a join auth.users u on u.id=a.user_id;
select case lower(u.email)
 when 'spicynetwork75@gmail.com' then 'authorised_admin'
 when 'nehanikitanand@gmail.com' then 'reported_other_account'
 else 'other_actor' end as actor,
 a.action,count(*) as actions,max(a.created_at) as latest
from private.audit a left join auth.users u on u.id=a.actor_id
where a.action='admin_review' group by 1,2;
select version,name from supabase_migrations.schema_migrations
where version>='20261024000000' order by version;
select to_regprocedure('private.admin_identity_allowed()') is not null as identity_guard_exists,
 position('admin_identity_allowed' in pg_get_functiondef('private.is_admin()'::regprocedure))>0 as admin_uses_identity_guard,
 position('admin_identity_allowed' in pg_get_functiondef('public.account_context()'::regprocedure))>0 as context_uses_identity_guard;
select event_type,state,count(*) as messages from private.email_outbox group by 1,2 order by 1,2;
select c.relname as public_table_without_rls
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;
rollback;
