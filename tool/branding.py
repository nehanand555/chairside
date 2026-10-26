"""Apply checked-in brand artwork to generated platform shells, without secrets."""
import hashlib
import json
from pathlib import Path
import re
import shutil
from xml.etree import ElementTree as ET

ASSETS = Path(__file__).resolve().parents[1] / "assets/branding/icons"
CREAM = "#faf9f0"
GREEN = "#153e37"
DESCRIPTION = "spicyself — discover local style professionals and book services."


def apply_branding(root):
    root = Path(root)

    def icon(size, destination):
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ASSETS / f"{size}.png", destination)

    web = root / "web"
    if web.exists():
        version = hashlib.sha256((ASSETS / "32.png").read_bytes()).hexdigest()[:12]
        icon(32, web / "favicon.png")
        for size in (192, 512):
            for name in (f"Icon-{size}.png", f"Icon-maskable-{size}.png"):
                icon(size, web / "icons" / name)
        manifest_path = web / "manifest.json"
        manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
        manifest.update(name="spicyself", short_name="spicyself", start_url=".",
                        display="standalone", background_color=CREAM, theme_color=GREEN,
                        description=DESCRIPTION)
        manifest["icons"] = [
            {"src": f"icons/Icon-{prefix}{size}.png?v={version}", "sizes": f"{size}x{size}",
             "type": "image/png", "purpose": purpose}
            for prefix, purpose in (("", "any"), ("maskable-", "maskable"))
            for size in (192, 512)
        ]
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        index = web / "index.html"
        if index.exists():
            html = re.sub(r"<title>.*?</title>", "<title>spicyself — find your next look</title>", index.read_text())
            for name, value in (("description", DESCRIPTION),
                                ("apple-mobile-web-app-title", "spicyself"),
                                ("theme-color", GREEN)):
                tag = f'<meta name="{name}" content="{value}">'
                pattern = rf'<meta\s+name="{name}"[^>]*>'
                if re.search(pattern, html):
                    html = re.sub(pattern, tag, html)
                else:
                    html = html.replace("</head>", f"  {tag}\n</head>")
            for asset in ("favicon.png", "icons/Icon-192.png", "manifest.json"):
                html = re.sub(
                    rf'href="{re.escape(asset)}(?:\?[^"\s]*)?"',
                    f'href="{asset}?v={version}"', html)
            index.write_text(html)

    ios = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    if (root / "ios/Runner").exists():
        images = []
        specs = (("iphone", (20, 29, 40, 60), (2, 3)),
                 ("ipad", (20, 29, 40, 76), (1, 2)),
                 ("ipad", (83.5,), (2,)), ("ios-marketing", (1024,), (1,)))
        for idiom, sizes, scales in specs:
            for size in sizes:
                for scale in scales:
                    name = f"Icon-App-{size}x{size}@{scale}x.png"
                    icon(int(size * scale), ios / name)
                    images.append({"size": f"{size}x{size}", "idiom": idiom,
                                   "filename": name, "scale": f"{scale}x"})
        # Replace even legacy unreferenced Flutter icons left in an existing shell.
        for size in (20, 29, 40):
            icon(size, ios / f"Icon-App-{size}x{size}@1x.png")
        (ios / "Contents.json").write_text(json.dumps({"images": images,
            "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")

    android = root / "android/app/src/main"
    if android.exists():
        for density, size, foreground in (("mdpi", 48, 108), ("hdpi", 72, 162),
                ("xhdpi", 96, 216), ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432)):
            folder = android / "res" / f"mipmap-{density}"
            icon(size, folder / "ic_launcher.png")
            icon(size, folder / "ic_launcher_round.png")
            icon(foreground, folder / "ic_launcher_foreground.png")
        colors = android / "res/values/colors.xml"
        colors.parent.mkdir(parents=True, exist_ok=True)
        colors.write_text('<?xml version="1.0" encoding="utf-8"?>\n'
                          '<resources>\n'
                          f'  <color name="spicyself_icon_background">{CREAM}</color>\n'
                          '</resources>\n')
        adaptive = android / "res/mipmap-anydpi-v26"
        adaptive.mkdir(parents=True, exist_ok=True)
        xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
               '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
               '  <background android:drawable="@color/spicyself_icon_background" />\n'
               '  <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
               '</adaptive-icon>\n')
        for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
            (adaptive / name).write_text(xml)
        path = android / "AndroidManifest.xml"
        if path.exists():
            ns = "http://schemas.android.com/apk/res/android"
            ET.register_namespace("android", ns)
            doc = ET.parse(path)
            app = doc.getroot().find("application")
            app.set(f"{{{ns}}}icon", "@mipmap/ic_launcher")
            app.set(f"{{{ns}}}roundIcon", "@mipmap/ic_launcher_round")
            doc.write(path, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    apply_branding(Path(__file__).resolve().parents[1])
