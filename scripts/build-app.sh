#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: bash scripts/build-app.sh [debug|release]" >&2
    exit 1
fi
# Keep the signing identity stable across rebuilds so Keychain grants survive.
identity=${MINUTES_SIGN_IDENTITY:-}
if [[ -z "$identity" ]]; then
    identities=$(security find-identity -v -p codesigning)
    development_ids=()
    while IFS= read -r fingerprint; do
        [[ -n "$fingerprint" ]] && development_ids+=("$fingerprint")
    done < <(printf '%s\n' "$identities" | sed -nE 's/.* ([[:xdigit:]]{40}) "Apple Development:.*$/\1/p')
    if [[ ${#development_ids[@]} -ne 1 ]]; then
        echo "Set MINUTES_SIGN_IDENTITY to an identity from security find-identity -v -p codesigning." >&2
        echo "For an explicit ad-hoc build, use MINUTES_SIGN_IDENTITY=-; Keychain prompts may recur after rebuilding." >&2
        exit 1
    fi
    identity=${development_ids[0]}
fi
release_build=${MINUTES_RELEASE_BUILD:-0}
enable_updates=${MINUTES_ENABLE_UPDATES:-$release_build}
if [[ "$enable_updates" == 1 ]]; then
    python3 scripts/configure-updates.py --validate
fi
if [[ "$release_build" == 1 && "$identity" == - ]]; then
    echo "Release builds require Developer ID signing." >&2
    exit 1
fi
expected_sdk="$(xcrun --sdk macosx --show-sdk-version)"
minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
# Swift Build in the current Xcode toolchain stamps the deployment version as
# the SDK version, even when compiling with the selected SDK. Pass both values
# explicitly so system controls use the appearance for the SDK we build with.
bash scripts/swift-local.sh build -c "$configuration" --product Minutes \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -Xlinker -platform_version -Xlinker macos \
    -Xlinker "$minimum_macos" -Xlinker "$expected_sdk"
binary_dir="$(bash scripts/swift-local.sh build -c "$configuration" --show-bin-path)"
built_sdk="$(xcrun vtool -show-build "$binary_dir/Minutes" | awk '$1 == "sdk" { print $2; exit }')"
if [[ "$built_sdk" != "$expected_sdk" ]]; then
    echo "Minutes records SDK $built_sdk, but Xcode selects $expected_sdk; refusing to package it." >&2
    exit 1
fi
app="$PWD/dist/Minutes.app"
rm -rf "$app"
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
    cp -Rf "$bundle" "$app/Contents/Resources/"
done
for library in "$binary_dir/"*.dylib; do
    cp "$library" "$app/Contents/Frameworks/"
done
sparkle="$app/Contents/Frameworks/Sparkle.framework"
ditto "$binary_dir/Sparkle.framework" "$sparkle"
# This app is not sandboxed; Sparkle's sandbox XPC services are unnecessary.
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
if [[ "$enable_updates" == 1 ]]; then
    python3 scripts/configure-updates.py "$app/Contents/Info.plist"
fi
code_args=(--timestamp=none)
app_args=()
if [[ "$release_build" == 1 ]]; then
    code_args=(--options runtime --timestamp)
    app_args=(--entitlements Resources/Release.entitlements)
fi
for library in "$app/Contents/Frameworks/"*.dylib; do
    codesign --force --sign "$identity" "${code_args[@]}" "$library"
done
for nested in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"; do
    codesign --force --sign "$identity" "${code_args[@]}" "$nested"
done
codesign --force --sign "$identity" "${code_args[@]}" "${app_args[@]}" "$app"
if [[ "$release_build" == 1 ]]; then
    signature_info=$(codesign -d --verbose=2 "$app" 2>&1)
    if [[ "$signature_info" != *"Authority=Developer ID Application:"* ]]; then
        echo "Release builds require a Developer ID Application certificate." >&2
        exit 1
    fi
fi
codesign --verify --deep --strict "$app"
# Mark the bundle changed so Launch Services can invalidate cached metadata/icons.
touch "$app"
echo "Built $app"
