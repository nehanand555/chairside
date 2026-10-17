"""Generate Flutter's platform shells and apply the required public client configuration.

Run from the repository root. Secret server keys never belong in this process.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def configure(platform="web"):
    with tempfile.TemporaryDirectory(prefix="chairside-platforms-") as temp:
        shell = Path(temp) / "chairside"
        subprocess.run(["flutter", "create", "--empty", "--platforms=android,ios,web", "--org=nz.chairside", "--project-name=chairside", str(shell)], check=True)
        for platform in ("android", "ios", "web"):
            if not (ROOT / platform).exists():
                shutil.copytree(shell / platform, ROOT / platform)
    ns = "http://schemas.android.com/apk/res/android"
    ET.register_namespace("android", ns)
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    doc = ET.parse(manifest)
    root = doc.getroot()
    for permission in ("INTERNET", "ACCESS_COARSE_LOCATION", "ACCESS_FINE_LOCATION"):
        value = f"android.permission.{permission}"
        if not any(p.get(f"{{{ns}}}name") == value for p in root.findall("uses-permission")):
            ET.SubElement(root, "uses-permission", {f"{{{ns}}}name": value})
    application = root.find("application")
    application.set(f"{{{ns}}}label", "Chairside")
    for meta in list(application.findall("meta-data")):
        if meta.get(f"{{{ns}}}name") == "com.google.android.geo.API_KEY":
            application.remove(meta)
    ET.SubElement(application, "meta-data", {f"{{{ns}}}name": "com.google.android.geo.API_KEY", f"{{{ns}}}value": os.getenv("GOOGLE_MAPS_ANDROID_KEY", "")})
    doc.write(manifest, encoding="utf-8", xml_declaration=True)
    plist = ROOT / "ios/Runner/Info.plist"
    with plist.open("rb") as f:
        info = plistlib.load(f)
    info.update(CFBundleDisplayName="Chairside", NSLocationWhenInUseUsageDescription="Find hair professionals near you, only when you choose Near me.", NSPhotoLibraryUsageDescription="Choose photos to publish on your business portfolio.", GMapsKey=os.getenv("GOOGLE_MAPS_IOS_KEY", ""))
    with plist.open("wb") as f:
        plistlib.dump(info, f)
    delegate = ROOT / "ios/Runner/AppDelegate.swift"
    swift = delegate.read_text()
    if "import GoogleMaps" not in swift:
        swift = "import GoogleMaps\n" + swift
    if "GMSServices.provideAPIKey" not in swift:
        pattern = r"(override func application\([\s\S]*?\) -> Bool \{)"
        swift, count = re.subn(pattern, r'\1\n    if let key = Bundle.main.object(forInfoDictionaryKey: "GMapsKey") as? String, !key.isEmpty { GMSServices.provideAPIKey(key) }', swift, count=1)
        if count != 1:
            raise RuntimeError("Flutter AppDelegate template changed; inspect native map initialization")
    delegate.write_text(swift)
    podfile = ROOT / "ios/Podfile"
    if podfile.exists():
        podfile.write_text(re.sub(r"#?\s*platform :ios, '[0-9.]+'", "platform :ios, '15.0'", podfile.read_text()))
    project = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    project.write_text(re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.0;", project.read_text()))
    web = ROOT / "web/index.html"
    html = web.read_text()
    html = re.sub(r'\s*<script[^>]*data-chairside-maps[^>]*></script>', '', html)
    key = os.getenv("GOOGLE_MAPS_WEB_KEY", "")
    if key:
        from urllib.parse import quote
        html = html.replace("</head>", f'<script data-chairside-maps src="https://maps.googleapis.com/maps/api/js?key={quote(key, safe="")}"></script>\n</head>')
    html = html.replace("<title>chairside</title>", "<title>Chairside — find your next chair</title>")
    web.write_text(html)
    defines = {key: os.getenv(key, "") for key in ("SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "GOOGLE_MAPS_WEB_KEY", "SUPPORT_EMAIL")}
    defines["MAPS_ENABLED"] = bool(os.getenv({"web": "GOOGLE_MAPS_WEB_KEY", "android": "GOOGLE_MAPS_ANDROID_KEY", "ios": "GOOGLE_MAPS_IOS_KEY", "ios-simulator": "GOOGLE_MAPS_IOS_KEY"}[platform]))
    (ROOT / "build-config.json").write_text(json.dumps(defines))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=["web", "android", "ios", "ios-simulator"], default="web")
    configure(parser.parse_args().platform)
