#!/bin/zsh
set -eu
cd "${0:A:h}/.."
DESTINATION="$PWD/build/Cats in Menubar.app"
mkdir -p "$PWD/build"
# Persistent app-specific identity keeps Accessibility grants stable across rebuilds.
IDENTITY="${CATS_SIGNING_IDENTITY:-Cats in Menubar Local Signing}"
security find-identity -v -p codesigning | /usr/bin/grep -F "\"$IDENTITY\"" >/dev/null || {
  echo "Missing signing identity: $IDENTITY. Run zsh tools/setup_signing.sh first." >&2
  exit 1
}
STAGING=$(mktemp -d "$PWD/build/.candidate.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Cats in Menubar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/build/module-cache"
xcrun swift -module-cache-path "$PWD/build/module-cache" tools/prepare_assets.swift "$APP/Contents/Resources/Cats"
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$PWD/build/module-cache" \
  -framework Cocoa -framework SwiftUI -framework ApplicationServices -framework IOKit -framework SystemConfiguration -framework ServiceManagement -framework CoreWLAN -framework CoreLocation \
  app/macos/*.swift -o "$APP/Contents/MacOS/CatsInMenubar"
"$APP/Contents/MacOS/CatsInMenubar" --render-iconset "$STAGING/AppIcon.iconset"
iconutil -c icns "$STAGING/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
# The updater runs this bundled installer to swap /Applications safely.
cp tools/install_app.py "$APP/Contents/Resources/"
# The built commit is how the updater compares this app with the stable branch.
REVISION=$(git rev-parse HEAD)
BUILD=$(git rev-list --count HEAD)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CatsInMenubar</string>
<key>CFBundleIdentifier</key><string>local.catsinmenubar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Cats in Menubar</string>
<key>CFBundleDisplayName</key><string>Cats in Menubar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>CatsSourceRevision</key><string>$REVISION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocationUsageDescription</key><string>Only to show the name of your Wi-Fi network in the panel. Your location is never read.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>Only to show the name of your Wi-Fi network in the panel. Your location is never read.</string>
</dict></plist>
PLIST
codesign --force --sign "$IDENTITY" --identifier local.catsinmenubar "$APP"
codesign --verify --deep --strict "$APP"
rm -rf "$DESTINATION"
mv "$APP" "$DESTINATION"
echo "Built: $DESTINATION"
