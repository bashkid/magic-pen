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
swift build -c release

APP="MagicPen.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/MagicPen "$APP/Contents/MacOS/MagicPen"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# The SPM resource bundle (icons) that the MagicPen executable loads at
# runtime via Bundle.module - must sit next to the binary for release builds.
RES_BUNDLE="$APP/Contents/MacOS/MagicPen_MagicPen.bundle"
if [ -d .build/release/MagicPen_MagicPen.bundle ]; then
  cp -R .build/release/MagicPen_MagicPen.bundle "$APP/Contents/MacOS/"
  # codesign refuses to seal a directory named *.bundle unless it looks like
  # a real CFBundle (needs an Info.plist) - SPM's generated one is just a
  # loose resource folder, so give it a minimal plist to satisfy codesign.
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

echo "Signing (ad-hoc, for a stable local identity)..."
codesign --force --deep --sign - "$APP"

echo "Done: $(pwd)/$APP"
echo "Launch with: open $APP"
