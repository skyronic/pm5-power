#!/bin/sh
# Builds build/PowerView.dmg for a release: the app plus an Applications shortcut to drag it onto.
set -e
cd "$(dirname "$0")"
./build.sh
STAGE=build/dmg
DMG=build/PowerView.dmg
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/PowerView.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname PowerView -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
echo "Built $(pwd)/$DMG"
