#!/bin/sh
# Builds PowerView.app next to this script. Usage: ./build.sh && open PowerView.app
set -e
cd "$(dirname "$0")"
APP=PowerView.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macos14 PowerView.swift -o "$APP/Contents/MacOS/PowerView"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.powerview</string>
  <key>CFBundleName</key><string>PowerView</string>
  <key>CFBundleExecutable</key><string>PowerView</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>PowerView reads live power from your Concept2 PM5.</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
