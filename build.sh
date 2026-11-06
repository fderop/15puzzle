#!/bin/bash
# Builds build/FifteenPuzzle.app without Xcode (needs Command Line Tools). Use --run to launch.
set -euo pipefail
cd "$(dirname "$0")"
A=build/FifteenPuzzle.app
rm -rf "$A"; mkdir -p "$A/Contents/MacOS"
swiftc -O -wmo -target "$(uname -m)-apple-macos14.0" -o "$A/Contents/MacOS/FifteenPuzzle" FifteenPuzzle/*.swift
sed -e 's/$(EXECUTABLE_NAME)/FifteenPuzzle/;s/$(PRODUCT_BUNDLE_IDENTIFIER)/com.fderop.FifteenPuzzle/;s/$(PRODUCT_NAME)/FifteenPuzzle/;s/$(MACOSX_DEPLOYMENT_TARGET)/14.0/' FifteenPuzzle/Info.plist > "$A/Contents/Info.plist"
codesign --force --sign - "$A"
echo "Built $A"
[ "${1:-}" = "--run" ] && open "$A"
exit 0
