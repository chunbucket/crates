#!/bin/bash
# Build Cuts.app from the SPM package (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Cuts.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Cuts "$APP/Contents/MacOS/Cuts"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force -s - "$APP" >/dev/null 2>&1

echo "Built $APP"
