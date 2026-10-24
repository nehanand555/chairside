# SpicySelf brand assets

`scissors.png` is the supplied “Minimalist Forest Green Scissors Icon.png”,
copied without changing the artwork. It contains the scissors on its original
warm cream background. The app header adds the lowercase `spicyself` wordmark
in Flutter; all launcher icons and favicons contain only the scissors.

`icons/` contains square PNG sizes exported directly from that image with macOS
`sips -z SIZE SIZE scissors.png --out icons/SIZE.png`. These checked-in exports
let Linux CI apply the branding without an image processing dependency.

`python3 tool/branding.py` applies only branding to existing local platform
shells. `tool/bootstrap.py` also applies it after generating shells, so CI builds
retain the artwork. Do not commit the generated platform shells or local keys.

Generated destinations:

- `web/favicon.png`, `web/icons/*.png`, `web/manifest.json`, `web/index.html`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/*`
- `android/app/src/main/res/mipmap-*/ic_launcher*.png`
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher*.xml`
- Android manifest icon references

The source image has no alpha channel, as required for the iOS marketing icon.
Its original inset keeps the scissors inside adaptive and maskable icon bounds.
