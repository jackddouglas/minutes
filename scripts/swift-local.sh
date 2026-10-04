#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# A mixed Command Line Tools install can retain a Swift 5 private manifest
# interface next to a Swift 6 library. Isolate its current public interface;
# do not modify the installed toolchain or the user's compiler caches.
toolchain_root="$(xcode-select -p)/usr/lib/swift/pm"
private_interface="$toolchain_root/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface"
if [[ -f "$private_interface" ]] && /usr/bin/grep -q 'Apple Swift version 5.10' "$private_interface" && swift --version | /usr/bin/grep -q 'Swift version 6'; then
    local_libs="$PWD/.build/manifest-libs"
    mkdir -p "$local_libs/ManifestAPI/PackageDescription.swiftmodule"
    public_interface="$toolchain_root/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface"
    local_interface="$local_libs/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface"
    if ! cmp -s "$public_interface" "$local_interface"; then
        cp "$public_interface" "$local_interface"
    fi
    ln -sf "$toolchain_root/ManifestAPI/libPackageDescription.dylib" "$local_libs/ManifestAPI/libPackageDescription.dylib"
    export SWIFTPM_CUSTOM_LIBS_DIR="$local_libs"
fi
if [[ "${1:-}" == "test" || "${1:-}" == "build" ]]; then
    testing_plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
    if [[ -f "$testing_plugins/libTestingMacros.dylib" ]]; then
        exec swift "$@" -Xswiftc -plugin-path -Xswiftc "$testing_plugins"
    fi
fi
exec swift "$@"
