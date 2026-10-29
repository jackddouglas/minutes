#!/bin/bash
# Creates a Minutes-specific signing key in Keychain; only its public key is saved here.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/swift-local.sh package resolve
tool=.build/artifacts/sparkle/Sparkle/bin/generate_keys
"$tool" --account app.minutes.meetings
key=$("$tool" --account app.minutes.meetings -p)
if [[ -f Resources/sparkle-public-key.txt && "$(cat Resources/sparkle-public-key.txt)" != "$key" ]]; then
    echo "Existing public key differs; refusing to rotate the published update identity." >&2
    exit 1
fi
printf '%s\n' "$key" > Resources/sparkle-public-key.txt
python3 scripts/configure-updates.py --validate
