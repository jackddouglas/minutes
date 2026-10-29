#!/bin/bash
# Prepare a notarized app and signed feed locally. Publishing is a separate step.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 2 ]]; then
    echo "Usage: bash scripts/release.sh VERSION BUILD_NUMBER" >&2
    exit 1
fi
export MINUTES_VERSION=$1 MINUTES_BUILD_NUMBER=$2 MINUTES_RELEASE_BUILD=1 MINUTES_ENABLE_UPDATES=1
: "${MINUTES_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
: "${MINUTES_NOTARY_PROFILE:?Set a notarytool Keychain profile}"
python3 scripts/configure-updates.py --validate
[[ "$(uname -m)" == arm64 ]] || { echo "This release script packages Apple Silicon builds." >&2; exit 1; }
key=$(.build/artifacts/sparkle/Sparkle/bin/generate_keys --account app.minutes.meetings -p)
[[ "$key" == "$(cat Resources/sparkle-public-key.txt)" ]] || {
    echo "The Keychain signing key does not match the public key shipped by Minutes." >&2
    exit 1
}
out="$PWD/dist/releases/v$MINUTES_VERSION"
[[ ! -e "$out" ]] || { echo "Refusing to overwrite $out" >&2; exit 1; }
bash scripts/build-app.sh release
mkdir -p "$out"
archive="$out/Minutes-$MINUTES_VERSION-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent dist/Minutes.app "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$MINUTES_NOTARY_PROFILE" --wait
xcrun stapler staple dist/Minutes.app
xcrun stapler validate dist/Minutes.app
codesign --verify --deep --strict dist/Minutes.app
spctl --assess --type execute dist/Minutes.app
rm "$archive"
ditto -c -k --sequesterRsrc --keepParent dist/Minutes.app "$archive"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --account app.minutes.meetings --maximum-deltas 0 \
    --download-url-prefix "https://github.com/jackddouglas/minutes/releases/download/v$MINUTES_VERSION/" \
    -o "$out/appcast.xml" "$out"
grep -q 'sparkle-signatures' "$out/appcast.xml"
echo "Prepared $archive and $out/appcast.xml. Nothing has been published."
