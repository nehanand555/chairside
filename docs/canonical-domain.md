# Canonical public domain

The public app and web Auth return URL are `https://www.spicyself.com/`.
`spicyself.com`, the old production Pages address, and its preview aliases redirect
to www before Flutter loads. Paths and query parameters are preserved. Hosting
project identifiers and native bundle IDs remain unchanged.

`tool/pages_worker.mjs` is copied to the Pages deployment as `_worker.js`.
Cloudflare Pages does not support host-level rules in a static `_redirects` file,
so this worker redirects alias hosts and delegates official-host requests to
`env.ASSETS.fetch` without altering application assets.

The `Configure canonical spicyself Auth domain` workflow uses the existing GitHub
`staging` environment. It requires the `SUPABASE_ACCESS_TOKEN` secret and
`SUPABASE_URL` variable; optional `SUPABASE_PROJECT_REF` must match that URL.
It reads hosted Auth config, patches only `site_url`/`uri_allow_list`, and reads
back those two settings to verify them. Existing non-Pages/native/development
callbacks remain allowed. OAuth provider credentials, MFA policy, roles, tables
and migrations are not updated. Configuration responses and credentials are
never printed.

The same targeted workflow sets the public `ALLOWED_ORIGINS` Edge configuration
to www, the bare domain and the old Pages origin during transition. No API key,
worker secret, provider credential or service-role key is replaced. Live CORS
preflight must be checked after the workflow to verify this runtime change.

The Dart login code always uses www for deployed aliases; local development
retains its own origin so PKCE browser storage stays with the correct origin.
Native callbacks remain `nz.nehanand.spicyself://login-callback/`.
