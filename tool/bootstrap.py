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
        for shell_platform in ("android", "ios", "web"):
            if not (ROOT / shell_platform).exists():
                shutil.copytree(shell / shell_platform, ROOT / shell_platform)
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
    activity = application.find("activity")
    # Supabase's app_links handler owns OAuth callbacks, not Flutter's router.
    deep_link_meta = next((m for m in activity.findall("meta-data") if m.get(f"{{{ns}}}name") == "flutter_deeplinking_enabled"), None)
    if deep_link_meta is None:
        deep_link_meta = ET.SubElement(activity, "meta-data")
    deep_link_meta.set(f"{{{ns}}}name", "flutter_deeplinking_enabled")
    deep_link_meta.set(f"{{{ns}}}value", "false")
    if not any(d.get(f"{{{ns}}}scheme") == "nz.chairside.chairside" for d in activity.findall("intent-filter/data")):
        intent = ET.SubElement(activity, "intent-filter")
        ET.SubElement(intent, "action", {f"{{{ns}}}name": "android.intent.action.VIEW"})
        for category in ("DEFAULT", "BROWSABLE"):
            ET.SubElement(intent, "category", {f"{{{ns}}}name": f"android.intent.category.{category}"})
        ET.SubElement(intent, "data", {f"{{{ns}}}scheme": "nz.chairside.chairside", f"{{{ns}}}host": "login-callback", f"{{{ns}}}path": "/"})
    doc.write(manifest, encoding="utf-8", xml_declaration=True)
    plist = ROOT / "ios/Runner/Info.plist"
    with plist.open("rb") as f:
        info = plistlib.load(f)
    info.update(CFBundleDisplayName="Chairside", NSLocationWhenInUseUsageDescription="Find hair professionals near you, only when you choose Near me.", NSPhotoLibraryUsageDescription="Choose photos to publish on your business portfolio.", GMapsKey=os.getenv("GOOGLE_MAPS_IOS_KEY", ""))
    url_types = info.setdefault("CFBundleURLTypes", [])
    if not any("nz.chairside.chairside" in entry.get("CFBundleURLSchemes", []) for entry in url_types):
        url_types.append({"CFBundleTypeRole": "Editor", "CFBundleURLName": "Chairside sign-in", "CFBundleURLSchemes": ["nz.chairside.chairside"]})
    info["FlutterDeepLinkingEnabled"] = False
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
        html = html.replace("</head>", f'<script data-chairside-maps src="https://maps.googleapis.com/maps/api/js?key={quote(key, safe="")}&v=quarterly"></script>\n</head>')
    html = html.replace("<title>chairside</title>", "<title>Chairside — find your next chair</title>")
    web.write_text(html)
    (ROOT / "web/_headers").write_text("/*\n  X-Content-Type-Options: nosniff\n  X-Frame-Options: DENY\n  Referrer-Policy: strict-origin-when-cross-origin\n  Permissions-Policy: geolocation=(self), camera=(), microphone=()\n  Content-Security-Policy: frame-ancestors 'none'; base-uri 'self'; object-src 'none'\n/index.html\n  Cache-Control: no-cache\n")
    defines = {key: os.getenv(key, "") for key in ("SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "GOOGLE_MAPS_WEB_KEY", "SUPPORT_EMAIL")}
    defines["MAPS_ENABLED"] = bool(os.getenv({"web": "GOOGLE_MAPS_WEB_KEY", "android": "GOOGLE_MAPS_ANDROID_KEY", "ios": "GOOGLE_MAPS_IOS_KEY", "ios-simulator": "GOOGLE_MAPS_IOS_KEY"}[platform]))
    (ROOT / "build-config.json").write_text(json.dumps(defines))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=["web", "android", "ios", "ios-simulator"], default="web")
    configure(parser.parse_args().platform)
