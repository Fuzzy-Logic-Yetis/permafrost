#!/bin/sh
# Builds Permafrost.app from the SPM package (ADR-009 — no Xcode required).
# Output: dist/Permafrost.app, ad-hoc signed.
#
# Note: every ad-hoc re-sign is a new identity to macOS — re-grant Accessibility
# after rebuilding (System Settings → Privacy & Security → Accessibility).
set -e
cd "$(dirname "$0")/.."

VERSION="0.4.0"
IDENTIFIER="com.fuzzylogicyetis.Permafrost"
APP="dist/Permafrost.app"

echo "Building release binary..."
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "Assembling ${APP}..."
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Permafrost" "$APP/Contents/MacOS/Permafrost"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleExecutable</key>
    <string>Permafrost</string>
    <key>CFBundleIdentifier</key>
    <string>${IDENTIFIER}</string>
    <key>CFBundleName</key>
    <string>Permafrost</string>
    <key>CFBundleDisplayName</key>
    <string>Permafrost</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Fuzzy Logic Yetis — MIT License</string>
</dict>
</plist>
PLIST

echo "Signing (ad-hoc)..."
codesign --force --sign - "$APP"

echo "Done: $APP"
echo "Run with: open $APP"
