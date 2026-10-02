#!/bin/sh
# Builds build/PowerView.app (universal). Usage: ./build.sh && open build/PowerView.app
set -e
cd "$(dirname "$0")"
ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/PowerView"
APP=build/PowerView.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/PowerView"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
