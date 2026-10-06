#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: bash scripts/build-app.sh [debug|release]" >&2
    exit 1
fi
expected_sdk="$(xcrun --sdk macosx --show-sdk-version)"
minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
# Swift Build in the current Xcode toolchain stamps the deployment version as
# the SDK version, even when compiling with the selected SDK. Pass both values
# explicitly so system controls use the appearance for the SDK we build with.
bash scripts/swift-local.sh build -c "$configuration" --product Minutes \
    -Xlinker -platform_version -Xlinker macos \
    -Xlinker "$minimum_macos" -Xlinker "$expected_sdk"
binary_dir="$(bash scripts/swift-local.sh build -c "$configuration" --show-bin-path)"
built_sdk="$(xcrun vtool -show-build "$binary_dir/Minutes" | awk '$1 == "sdk" { print $2; exit }')"
if [[ "$built_sdk" != "$expected_sdk" ]]; then
    echo "Minutes records SDK $built_sdk, but Xcode selects $expected_sdk; refusing to package it." >&2
    exit 1
fi
app="$PWD/dist/Minutes.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary_dir/Minutes" "$app/Contents/MacOS/Minutes"
cp Resources/Info.plist "$app/Contents/Info.plist"
# Compile the Icon Composer source for adaptive appearances and legacy macOS.
xcrun actool "$PWD/Resources/Minutes.icon" \
    --compile "$app/Contents/Resources" \
    --platform macosx --minimum-deployment-target "$minimum_macos" \
    --app-icon Minutes --output-partial-info-plist "$PWD/.build/icon-info.plist" \
    --output-format human-readable-text
shopt -s nullglob
for bundle in "$binary_dir/"*.bundle; do
    cp -R "$bundle" "$app/Contents/Resources/"
done
for library in "$binary_dir/"*.dylib; do
    cp "$library" "$app/Contents/Frameworks/"
done
codesign --force --deep --sign - "$app"
# Mark the bundle changed so Launch Services can invalidate cached metadata/icons.
touch "$app"
echo "Built $app"
