#!/bin/bash
# Builds build/fifteen.app without Xcode (needs Command Line Tools). Use --run to launch.
set -euo pipefail
cd "$(dirname "$0")"
A=build/fifteen.app
rm -rf "$A"; mkdir -p "$A/Contents/MacOS" "$A/Contents/Resources"
swiftc -O -wmo -target "$(uname -m)-apple-macos14.0" -o "$A/Contents/MacOS/fifteen" FifteenPuzzle/*.swift
sed -e 's/$(EXECUTABLE_NAME)/fifteen/;s/$(PRODUCT_BUNDLE_IDENTIFIER)/com.fderop.FifteenPuzzle/;s/$(PRODUCT_NAME)/fifteen/;s/$(MACOSX_DEPLOYMENT_TARGET)/14.0/' FifteenPuzzle/Info.plist > "$A/Contents/Info.plist"
cp Icon/AppIcon.icns "$A/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$A"
echo "Built $A"
[ "${1:-}" = "--run" ] && open "$A"
exit 0
