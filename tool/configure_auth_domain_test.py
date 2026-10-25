import contextlib
import io
import json
import os
import unittest
from unittest.mock import patch

import configure_auth_domain as config


class AuthDomainTests(unittest.TestCase):
    def test_only_urls_change_and_existing_native_dev_callbacks_survive(self):
        current = {'site_url': 'https://chairside-staging.pages.dev',
                   'uri_allow_list': 'http://localhost:5000/**,https://chairside-staging.pages.dev/**,https://preview.chairside-staging.pages.dev/**,' + config.NATIVE,
                   'external_google_secret': 'private-test-value', 'mfa_totp_verify_enabled': True}
        desired = config.url_settings(current)
        self.assertEqual(set(desired), {'site_url', 'uri_allow_list'})
        self.assertEqual(desired['site_url'], config.SITE)
        self.assertNotIn('pages.dev', desired['uri_allow_list'])
        self.assertIn('http://localhost:5000/**', desired['uri_allow_list'])
        self.assertIn(config.NATIVE, desired['uri_allow_list'])
        self.assertEqual(config.url_settings(desired), desired)
        self.assertTrue(current['mfa_totp_verify_enabled'])

    def test_updater_patches_only_urls_and_verifies_without_logging_credentials(self):
        ref = 'a' * 20
        old = {'site_url': 'https://chairside-staging.pages.dev', 'uri_allow_list': '',
               'external_google_secret': 'private-test-value'}
        desired = config.url_settings(old)
        responses = [io.StringIO(json.dumps(value)) for value in [old, desired, desired]]
        with patch.dict(os.environ, {'SUPABASE_ACCESS_TOKEN': 'test-token',
                                    'SUPABASE_PROJECT_REF': ref,
                                    'SUPABASE_URL': f'https://{ref}.supabase.co'}, clear=True), patch.object(config, 'urlopen', side_effect=responses) as request:
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                config.main()
        patch_request = request.call_args_list[1].args[0]
        self.assertEqual(patch_request.method, 'PATCH')
        self.assertEqual(json.loads(patch_request.data), desired)
        self.assertNotIn('test-token', output.getvalue())
        self.assertNotIn('private-test-value', output.getvalue())
        self.assertEqual(len(request.call_args_list), 3)

    def test_project_mismatch_prevents_all_network_calls(self):
        with patch.dict(os.environ, {'SUPABASE_ACCESS_TOKEN': 'test-token',
                                    'SUPABASE_PROJECT_REF': 'a' * 20,
                                    'SUPABASE_URL': 'https://' + 'b' * 20 + '.supabase.co'}, clear=True), patch.object(config, 'urlopen') as request:
            with self.assertRaisesRegex(ValueError, 'does not match'):
                config.main()
            request.assert_not_called()

    def test_public_origin_update_only_changes_the_origin_setting(self):
        ref = 'a' * 20
        desired = config.url_settings({'uri_allow_list': ''})
        responses = [io.StringIO(json.dumps(value)) for value in [desired, desired, {}]]
        with patch.dict(os.environ, {'SUPABASE_ACCESS_TOKEN': 'test-token',
                                    'SUPABASE_URL': f'https://{ref}.supabase.co',
                                    'CONFIGURE_PUBLIC_CORS': '1'}, clear=True), patch.object(config, 'urlopen', side_effect=responses) as request, contextlib.redirect_stdout(io.StringIO()):
            config.main()
        origin_request = request.call_args_list[-1].args[0]
        self.assertEqual(origin_request.method, 'POST')
        self.assertTrue(origin_request.full_url.endswith('/secrets'))
        body = json.loads(origin_request.data)
        self.assertEqual([item['name'] for item in body], ['ALLOWED_ORIGINS'])
        self.assertIn(config.SITE, body[0]['value'].split(','))
