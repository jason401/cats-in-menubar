#!/bin/zsh
set -eu
cd "${0:A:h}/.."
APP="$PWD/build/Cats in Menubar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/build/module-cache"
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$PWD/build/module-cache" \
  -framework Cocoa -framework SwiftUI -framework ApplicationServices \
  app/macos/*.swift -o "$APP/Contents/MacOS/CatsInMenubar"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CatsInMenubar</string>
<key>CFBundleIdentifier</key><string>local.catsinmenubar</string>
<key>CFBundleName</key><string>Cats in Menubar</string>
<key>CFBundleDisplayName</key><string>Cats in Menubar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# A fresh project's development signature; existing apps and signing identities are untouched.
# Set CATS_SIGNING_IDENTITY to a persistent identity for reliable Accessibility grants across rebuilds.
codesign --force --sign "${CATS_SIGNING_IDENTITY:--}" --identifier local.catsinmenubar "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
