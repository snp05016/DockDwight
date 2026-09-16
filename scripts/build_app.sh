#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

APP_NAME="DockDwight"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH" "$CONTENTS/MacOS/$APP_NAME"
chmod +x "$CONTENTS/MacOS/$APP_NAME"
BUILD_DIR="$(dirname "$BIN_PATH")"
for bundle in "$BUILD_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then cp -R "$bundle" "$CONTENTS/MacOS/"; cp -R "$bundle" "$CONTENTS/Resources/"; fi
done
cp -R Sources/DockDwightLib/Resources/* "$CONTENTS/Resources/"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DockDwight</string>
<key>CFBundleIdentifier</key><string>com.saumya.DockDwight</string>
<key>CFBundleName</key><string>DockDwight</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP_BUNDLE"
echo "$ROOT_DIR/$APP_BUNDLE"
