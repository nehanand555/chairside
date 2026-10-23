"""Verify that generated native OAuth handlers agree and remain idempotent."""
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET

import bootstrap


class BootstrapTests(unittest.TestCase):
    def create_shell(self, command, **_):
        shell = Path(command[-1])
        (shell / 'android/app/src/main').mkdir(parents=True)
        (shell / 'android/app/src/main/AndroidManifest.xml').write_text(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application><activity android:name=".MainActivity" android:launchMode="singleTop">'
            '</activity></application></manifest>')
        (shell / 'ios/Runner').mkdir(parents=True)
        (shell / 'ios/Runner/Info.plist').write_bytes(plistlib.dumps({}))
        (shell / 'ios/Runner/AppDelegate.swift').write_text(
            'override func application(_ application: UIApplication) -> Bool { return true }')
        (shell / 'ios/Runner.xcodeproj').mkdir()
        (shell / 'ios/Runner.xcodeproj/project.pbxproj').write_text('IPHONEOS_DEPLOYMENT_TARGET = 13.0; PRODUCT_BUNDLE_IDENTIFIER = nz.chairside.chairside;')
        (shell / 'web').mkdir()
        (shell / 'web/index.html').write_text('<html><head></head></html>')

    def test_web_maps_loader_and_defines_use_build_environment(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with patch.object(bootstrap, 'ROOT', root), patch.object(
                bootstrap.subprocess, 'run', side_effect=self.create_shell
            ), patch.dict(os.environ, {'GOOGLE_MAPS_WEB_KEY': 'dummy-web-value',
                                       'GOOGLE_MAPS_IOS_KEY': ''}):
                bootstrap.configure('web')
                bootstrap.configure('web')
            html = (root / 'web/index.html').read_text()
            self.assertEqual(html.count('data-chairside-maps'), 1)
            self.assertIn('https://maps.googleapis.com/maps/api/js?key=dummy-web-value', html)
            config = json.loads((root / 'build-config.json').read_text())
            self.assertEqual(config['GOOGLE_MAPS_WEB_KEY'], 'dummy-web-value')
            self.assertTrue(config['MAPS_ENABLED'])

    def test_native_callback_handlers_and_platform_keys(self):
        for platform in ('android', 'ios', 'ios-simulator', 'web'):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                with patch.object(bootstrap, 'ROOT', root), patch.object(
                    bootstrap.subprocess, 'run', side_effect=self.create_shell
                ), patch.dict(os.environ, {'GOOGLE_MAPS_ANDROID_KEY': 'android-key',
                                           'GOOGLE_MAPS_IOS_KEY': 'ios-key',
                                           'GOOGLE_MAPS_WEB_KEY': ''}):
                    bootstrap.configure(platform)
                    bootstrap.configure(platform)
                ns = {'a': 'http://schemas.android.com/apk/res/android'}
                manifest = ET.parse(root / 'android/app/src/main/AndroidManifest.xml')
                data = manifest.findall('.//intent-filter/data')
                self.assertEqual(len(data), 1)
                self.assertEqual(data[0].get('{%s}scheme' % ns['a']), 'nz.nehanand.spicyself')
                self.assertEqual(data[0].get('{%s}host' % ns['a']), 'login-callback')
                self.assertEqual(data[0].get('{%s}path' % ns['a']), '/')
                meta = manifest.find('.//activity/meta-data')
                self.assertEqual(meta.get('{%s}name' % ns['a']), 'flutter_deeplinking_enabled')
                self.assertEqual(meta.get('{%s}value' % ns['a']), 'false')
                info = plistlib.loads((root / 'ios/Runner/Info.plist').read_bytes())
                self.assertEqual(len(info['CFBundleURLTypes']), 1)
                self.assertEqual(info['CFBundleURLTypes'][0]['CFBundleURLSchemes'], ['nz.nehanand.spicyself'])
                self.assertFalse(info['FlutterDeepLinkingEnabled'])
                self.assertEqual(info['GMapsKey'], '$(GOOGLE_MAPS_IOS_KEY)')
                local = root / 'ios/Flutter/Maps.local.xcconfig'
                self.assertEqual(local.read_text(), 'GOOGLE_MAPS_IOS_KEY = ios-key\n')
                for mode in ('Debug', 'Release'):
                    text = (root / f'ios/Flutter/{mode}.xcconfig').read_text()
                    self.assertEqual(text.count('#include "Maps.local.xcconfig"'), 1)
                with patch.object(bootstrap, 'ROOT', root), patch.dict(
                    os.environ, {'GOOGLE_MAPS_IOS_KEY': ''}
                ):
                    bootstrap.configure_ios_maps()
                self.assertEqual(local.read_text(), 'GOOGLE_MAPS_IOS_KEY = ios-key\n')
                self.assertIn('PRODUCT_BUNDLE_IDENTIFIER = nz.nehanand.spicyself;', (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text())
                config = json.loads((root / 'build-config.json').read_text())
                self.assertEqual(config['MAPS_ENABLED'], platform != 'web')


if __name__ == '__main__':
    unittest.main()
