#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: bash scripts/build-app.sh [debug|release]" >&2
    exit 1
fi
bash scripts/swift-local.sh build -c "$configuration" --product Minutes
binary_dir="$(bash scripts/swift-local.sh build -c "$configuration" --show-bin-path)"
app="$PWD/dist/Minutes.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary_dir/Minutes" "$app/Contents/MacOS/Minutes"
cp Resources/Info.plist "$app/Contents/Info.plist"
# Compile the Icon Composer source for adaptive appearances and legacy macOS.
xcrun actool Resources/Minutes.icon \
    --compile "$app/Contents/Resources" \
    --platform macosx --minimum-deployment-target 15.0 \
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
