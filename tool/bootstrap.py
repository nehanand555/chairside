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

from branding import apply_branding

ROOT = Path(__file__).resolve().parents[1]
APP_ID = "nz.nehanand.spicyself"
LEGACY_APP_ID = "nz.chairside.chairside"


def configure_ios_maps():
    """Keep the native Maps key in a local file shared by all build modes."""
    flutter = ROOT / "ios/Flutter"
    flutter.mkdir(parents=True, exist_ok=True)
    local = flutter / "Maps.local.xcconfig"
    key = os.getenv("GOOGLE_MAPS_IOS_KEY", "").strip()
    if key:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", key):
            raise ValueError("GOOGLE_MAPS_IOS_KEY contains invalid characters")
        local.write_text(f"GOOGLE_MAPS_IOS_KEY = {key}\n")
    elif not local.exists():
        local.write_text("// Paste your Maps SDK for iOS key after the equals sign.\nGOOGLE_MAPS_IOS_KEY =\n")
    for name in ("Debug.xcconfig", "Release.xcconfig"):
        config = flutter / name
        text = config.read_text() if config.exists() else ""
        include = '#include "Maps.local.xcconfig"'
        if include not in text:
            config.write_text(text.rstrip() + "\n" + include + "\n")


def configure(platform="web"):
    with tempfile.TemporaryDirectory(prefix="chairside-platforms-") as temp:
        shell = Path(temp) / "chairside"
        subprocess.run(["flutter", "create", "--empty", "--platforms=android,ios,web", "--org=nz.nehanand", "--project-name=chairside", str(shell)], check=True)
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
    application.set(f"{{{ns}}}label", "SpicySelf")
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
    if not any(d.get(f"{{{ns}}}scheme") == APP_ID for d in activity.findall("intent-filter/data")):
        intent = ET.SubElement(activity, "intent-filter")
        ET.SubElement(intent, "action", {f"{{{ns}}}name": "android.intent.action.VIEW"})
        for category in ("DEFAULT", "BROWSABLE"):
            ET.SubElement(intent, "category", {f"{{{ns}}}name": f"android.intent.category.{category}"})
        ET.SubElement(intent, "data", {f"{{{ns}}}scheme": APP_ID, f"{{{ns}}}host": "login-callback", f"{{{ns}}}path": "/"})
    doc.write(manifest, encoding="utf-8", xml_declaration=True)
    plist = ROOT / "ios/Runner/Info.plist"
    with plist.open("rb") as f:
        info = plistlib.load(f)
    info.update(CFBundleDisplayName="SpicySelf", NSLocationWhenInUseUsageDescription="Find hair professionals near you, only when you choose Near me.", NSPhotoLibraryUsageDescription="Choose photos to publish on your business portfolio.", GMapsKey="$(GOOGLE_MAPS_IOS_KEY)")
    url_types = info.setdefault("CFBundleURLTypes", [])
    if not any(APP_ID in entry.get("CFBundleURLSchemes", []) for entry in url_types):
        url_types.append({"CFBundleTypeRole": "Editor", "CFBundleURLName": "SpicySelf sign-in", "CFBundleURLSchemes": [APP_ID]})
    info["FlutterDeepLinkingEnabled"] = False
    with plist.open("wb") as f:
        plistlib.dump(info, f)
    configure_ios_maps()
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
    project_text = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.0;", project.read_text())
    for old_id in (LEGACY_APP_ID, "nz.nehanand.chairside"):
        project_text = project_text.replace(old_id, APP_ID)
    project.write_text(project_text)
    # Set the Android application ID, while retaining Flutter's generated native namespace.
    for gradle_name in ("build.gradle.kts", "build.gradle"):
        gradle = ROOT / "android/app" / gradle_name
        if gradle.exists():
            gradle_text = gradle.read_text()
            for old_id in (LEGACY_APP_ID, "nz.nehanand.chairside"):
                gradle_text = gradle_text.replace(f'applicationId = "{old_id}"', f'applicationId = "{APP_ID}"')
                gradle_text = gradle_text.replace(f'applicationId "{old_id}"', f'applicationId "{APP_ID}"')
            gradle.write_text(gradle_text)
    web = ROOT / "web/index.html"
    html = web.read_text()
    html = re.sub(r'\s*<script[^>]*data-chairside-maps[^>]*></script>', '', html)
    key = os.getenv("GOOGLE_MAPS_WEB_KEY", "")
    if key:
        from urllib.parse import quote
        html = html.replace("</head>", f'<script data-chairside-maps src="https://maps.googleapis.com/maps/api/js?key={quote(key, safe="")}&v=quarterly"></script>\n</head>')
    html = html.replace("<title>spicyself</title>", "<title>SpicySelf — find your next look</title>")
    web.write_text(html)
    (ROOT / "web/_headers").write_text("/*\n  X-Content-Type-Options: nosniff\n  X-Frame-Options: DENY\n  Referrer-Policy: strict-origin-when-cross-origin\n  Permissions-Policy: geolocation=(self), camera=(), microphone=()\n  Content-Security-Policy: frame-ancestors 'none'; base-uri 'self'; object-src 'none'\n/index.html\n  Cache-Control: no-cache\n")
    defines = {key: os.getenv(key, "") for key in ("SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "GOOGLE_MAPS_WEB_KEY", "SUPPORT_EMAIL")}
    defines["MAPS_ENABLED"] = bool(os.getenv({"web": "GOOGLE_MAPS_WEB_KEY", "android": "GOOGLE_MAPS_ANDROID_KEY", "ios": "GOOGLE_MAPS_IOS_KEY", "ios-simulator": "GOOGLE_MAPS_IOS_KEY"}[platform]))
    (ROOT / "build-config.json").write_text(json.dumps(defines))
    apply_branding(ROOT)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=["web", "android", "ios", "ios-simulator"], default="web")
    configure(parser.parse_args().platform)
