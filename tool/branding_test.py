import json
from pathlib import Path
import struct
import tempfile
import unittest
from xml.etree import ElementTree as ET

import branding


def png_size(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError("Expected PNG")
    return struct.unpack(">II", data[16:24])


class BrandingTests(unittest.TestCase):
    def test_generated_platform_assets_and_existing_configuration(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "web").mkdir()
            index = root / "web/index.html"
            index.write_text('<head><title>chairside</title>'
                             '<script data-chairside-maps src="dummy-maps-loader"></script></head>')
            (root / "ios/Runner").mkdir(parents=True)
            local = root / "ios/Runner/Info.plist"
            local.write_text('Existing OAuth and Maps configuration')
            android = root / "android/app/src/main"
            android.mkdir(parents=True)
            manifest = android / "AndroidManifest.xml"
            manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                                '<application><meta-data android:name="maps" android:value="dummy"/>'
                                '<activity android:name="MainActivity"><intent-filter/></activity>'
                                '</application></manifest>')
            branding.apply_branding(root)
            snapshots = {p.relative_to(root): p.read_bytes() for p in root.rglob('*') if p.is_file()}
            branding.apply_branding(root)
            self.assertEqual(snapshots, {p.relative_to(root): p.read_bytes()
                                        for p in root.rglob('*') if p.is_file()})
            self.assertEqual(local.read_text(), 'Existing OAuth and Maps configuration')
            self.assertIn('dummy-maps-loader', index.read_text())
            self.assertEqual(len(ET.parse(manifest).findall('.//intent-filter')), 1)
            self.assertEqual(len(ET.parse(manifest).findall('.//meta-data')), 1)
            web = json.loads((root / 'web/manifest.json').read_text())
            self.assertEqual(web['name'], 'SpicySelf')
            self.assertEqual(web['background_color'], branding.CREAM)
            for item in web['icons']:
                self.assertEqual(png_size(root / 'web' / item['src'].split('?')[0]),
                                 tuple(map(int, item['sizes'].split('x'))))
            self.assertEqual(png_size(root / 'web/favicon.png'), (32, 32))
            ios = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
            for item in json.loads((ios / 'Contents.json').read_text())['images']:
                expected = int(float(item['size'].split('x')[0]) * int(item['scale'][0]))
                self.assertEqual(png_size(ios / item['filename']), (expected, expected))
            for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                                  ('xxhdpi', 144), ('xxxhdpi', 192)]:
                self.assertEqual(png_size(android / f'res/mipmap-{density}/ic_launcher.png'), (size, size))
            for path in (android / 'res/mipmap-anydpi-v26').glob('*.xml'):
                ET.parse(path)
