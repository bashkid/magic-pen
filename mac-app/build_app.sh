#!/bin/bash
# Builds MagicPen.app - a release binary wrapped in a real app bundle.
# A stable bundle identity matters here, not just convenience: macOS ties the
# Screen Recording permission grant to the app bundle's signature, so running
# the raw executable via `swift run` re-prompts (or silently fails) every
# rebuild, while `open MagicPen.app` keeps the same identity and keeps
# the permission you already granted.
set -euo pipefail
cd "$(dirname "$0")"

echo "Building release binary..."
swift build -c release "$@"
BUILD_PRODUCTS="$(swift build -c release --show-bin-path "$@")"

APP="MagicPen.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_PRODUCTS/MagicPen" "$APP/Contents/MacOS/MagicPen"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Bundle.module searches the app's resource directory for the icon bundle.
RES_BUNDLE="$APP/Contents/Resources/MagicPen_MagicPen.bundle"
if [ -d "$BUILD_PRODUCTS/MagicPen_MagicPen.bundle" ]; then
  cp -R "$BUILD_PRODUCTS/MagicPen_MagicPen.bundle" "$APP/Contents/Resources/"
  # Current SwiftPM emits a complete macOS bundle. Older toolchains emit a
  # flat resource folder that needs a plist before codesign can seal it.
  if [ ! -f "$RES_BUNDLE/Contents/Info.plist" ] && [ ! -f "$RES_BUNDLE/Info.plist" ]; then
    cat > "$RES_BUNDLE/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.magicpen.mac.resources</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
</dict>
</plist>
PLIST
  fi
fi

echo "Signing (ad-hoc, for a stable local identity)..."
codesign --force --deep --sign - "$APP"

echo "Done: $(pwd)/$APP"
echo "Launch with: open $APP"
