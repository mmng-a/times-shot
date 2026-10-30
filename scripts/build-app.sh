#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --disable-sandbox --cache-path /private/tmp/times-shot-swift-cache \
    -Xswiftc -module-cache-path -Xswiftc /private/tmp/times-shot-module-cache
binary_dir=$(swift build -c release --disable-sandbox --show-bin-path)
app="dist/Times Shot.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/TimesShot" "$app/Contents/MacOS/TimesShot"
cp Resources/Info.plist "$app/Contents/Info.plist"
ditto "$binary_dir/TimesShot_TimesShot.bundle" "$app/Contents/Resources/TimesShot_TimesShot.bundle"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app"
echo "Built: $app"
