#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $(uname -m) != arm64 ]]; then
    echo "Release packages must be built on Apple Silicon." >&2
    exit 1
fi
version=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "CFBundleShortVersionString must use major.minor.patch." >&2
    exit 1
fi

bash scripts/build-app.sh
codesign --verify --deep --strict 'dist/Times Shot.app'
archive="TimesShot-${version}-macos-arm64.zip"
rm -f "dist/$archive"
ditto -c -k --keepParent 'dist/Times Shot.app' "dist/$archive"
cd dist
shasum -a 256 "$archive" > "$archive.sha256"
echo "Packaged: dist/$archive"
cat "$archive.sha256"
