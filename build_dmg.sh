#!/bin/bash
# Exit immediately if any command fails
set -e

echo "🔨 Building OneTake in Release mode..."
swift build -c release

# Directory variables
BUILD_DIR=".build/release"
APP_DIR="OneTake.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Creating App bundle structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BUILD_DIR/OneTake" "$MACOS_DIR/"

# Copy resources
cp AppIcon.icns "$RESOURCES_DIR/"
cp AppIcon.png "$RESOURCES_DIR/"

# Copy SPM resources bundle
if [ -d "$BUILD_DIR/OneTake_OneTake.bundle" ]; then
    cp -R "$BUILD_DIR/OneTake_OneTake.bundle" "$RESOURCES_DIR/"
fi

echo "📝 Creating Info.plist..."
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.onetake.app</string>
    <key>CFBundleName</key>
    <string>OneTake</string>
    <key>CFBundleDisplayName</key>
    <string>OneTake</string>
    <key>CFBundleExecutable</key>
    <string>OneTake</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSCameraUsageDescription</key>
    <string>OneTake needs access to your camera to show your camera bubble in the recording.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>OneTake needs access to your microphone to record your voice.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>OneTake needs screen recording access to record your screen.</string>
    <key>LSUIElement</key>
    <string>0</string>
</dict>
</plist>
EOF

echo "🖋️ Ad-hoc code signing app bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "💿 Creating DMG package..."
DMG_NAME="OneTake.dmg"
rm -f "$DMG_NAME"

DMG_ROOT="dmg_root"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"

# Copy the app to the DMG root
cp -R "$APP_DIR" "$DMG_ROOT/"

echo "💾 Building DMG using create-dmg..."
create-dmg \
  --volname "OneTake" \
  --volicon "AppIcon.icns" \
  --background "installer_background.png" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 96 \
  --icon "OneTake.app" 146 200 \
  --hide-extension "OneTake.app" \
  --app-drop-link 454 200 \
  "$DMG_NAME" \
  "$DMG_ROOT/"

# Clean up temporary folders
rm -rf "$DMG_ROOT"

echo "✅ Success! Built OneTake.dmg"
