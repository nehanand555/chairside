"""Update only hosted Auth URL settings; never deploy schema, functions or roles."""
import json
import os
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

SITE = 'https://www.spicyself.com'
NATIVE = 'nz.nehanand.spicyself://login-callback/'


def legacy_redirect(value):
    host = (urlparse(value).hostname or '').lower()
    return host == 'chairside-staging.pages.dev' or host.endswith('.chairside-staging.pages.dev')


def url_settings(current):
    existing = current.get('uri_allow_list') or ''
    if not isinstance(existing, str):
        raise ValueError('Unexpected Auth redirect-list format; no settings changed.')
    redirects = [value.strip() for value in existing.split(',')
                 if value.strip() and not legacy_redirect(value.strip())]
    redirects.extend([SITE + '/', SITE + '/**', NATIVE])
    return {'site_url': SITE, 'uri_allow_list': ','.join(dict.fromkeys(redirects))}


def main():
    token = os.environ.get('SUPABASE_ACCESS_TOKEN', '').strip()
    project_url = urlparse(os.environ.get('SUPABASE_URL', ''))
    ref = os.environ.get('SUPABASE_PROJECT_REF', '').strip() or (project_url.hostname or '').removesuffix('.supabase.co')
    if not token or not re.fullmatch(r'[a-z0-9]{20}', ref):
        raise ValueError('Set staging SUPABASE_ACCESS_TOKEN and a valid Supabase project URL/reference.')
    if project_url.scheme != 'https' or project_url.hostname != ref + '.supabase.co':
        raise ValueError('SUPABASE_URL does not match the selected project; refusing to change Auth.')
    endpoint = f'https://api.supabase.com/v1/projects/{ref}/'

    def call(method, payload=None, resource='config/auth'):
        request = Request(endpoint + resource, method=method,
                          headers={'Authorization': 'Bearer ' + token,
                                   'Content-Type': 'application/json'},
                          data=None if payload is None else json.dumps(payload).encode())
        try:
            with urlopen(request, timeout=30) as response:
                return json.load(response)
        except HTTPError as error:
            raise ValueError(f'Auth configuration {method} failed (HTTP {error.code}). Check token permissions.') from None
        except (URLError, TimeoutError):
            raise ValueError('Auth configuration service unavailable; retry later.') from None

    current = call('GET')  # Other fields may contain credentials: never print this object.
    print('Previous Site URL used the legacy Pages domain:', legacy_redirect(str(current.get('site_url', ''))))
    desired = url_settings(current)
    if any(current.get(key) != value for key, value in desired.items()):
        call('PATCH', desired)
    verified = call('GET')
    if any(verified.get(key) != value for key, value in desired.items()):
        raise ValueError('Hosted Auth URL verification failed.')
    if os.environ.get('CONFIGURE_PUBLIC_CORS') == '1':
        # This is public origin configuration, not a credential. Keep the old
        # origin allowed while existing clients transition through the redirect.
        origins = ','.join([SITE, 'https://spicyself.com', 'https://chairside-staging.pages.dev'])
        call('POST', [{'name': 'ALLOWED_ORIGINS', 'value': origins}], resource='secrets')
        print('Public web Edge origins configured for the canonical domain.')
    print('Hosted Auth Site URL verified: ' + SITE)
    print('Official callback and native callback allowed; legacy Pages callbacks removed.')


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        print('::error::' + str(error), file=sys.stderr)
        sys.exit(1)
