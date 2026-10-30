#!/bin/bash
# Embed versioned release notes and sign the complete update feed.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 1 && "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Usage: bash scripts/generate-appcast.sh VERSION" >&2
    exit 1
}
version=$1
out="$PWD/dist/releases/v$version"
notes="$PWD/release-notes/$version.html"
archive="$out/Minutes-$version-macos-arm64.zip"
[[ -s "$notes" ]] || { echo "Missing release notes: $notes" >&2; exit 1; }
[[ -f "$archive" ]] || { echo "Missing release archive: $archive" >&2; exit 1; }
cp "$notes" "$out/Minutes-$version-macos-arm64.html"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --account app.minutes.meetings --maximum-deltas 0 --embed-release-notes \
    --download-url-prefix "https://github.com/jackddouglas/minutes/releases/download/v$version/" \
    -o "$out/appcast.xml" "$out"
python3 - "$out/appcast.xml" "$version" <<'PY'
import sys
import xml.etree.ElementTree as ET
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(sys.argv[1]).findall('./channel/item')
item = next(item for item in items if item.findtext(ns + 'shortVersionString') == sys.argv[2])
if not (item.findtext('description') or '').strip():
    raise SystemExit('Generated feed is missing embedded release notes')
PY
.build/artifacts/sparkle/Sparkle/bin/sign_update \
    --account app.minutes.meetings --verify "$out/appcast.xml"
