# SDK metadata verification (2026-10-06)

The Nix-installed app and the original local debug app recorded `minos 15.0`
and `sdk 15.0` in `LC_BUILD_VERSION`, despite Xcode selecting macOS SDK 27.0.

A minimal Swift executable and a direct invocation of the app's saved link
command recorded SDK 27.0. Both an incremental relink and a clean build through
Swift Build recorded SDK 15.0. This isolates the discrepancy to the Swift Build
execution path in the installed Swift 6.4/Xcode toolchain; its internal cause
has not been established.

The packaging script now passes the minimum macOS version from Info.plist and
the selected SDK version explicitly via the linker's `-platform_version`, and
rejects SDK metadata that does not match. The icon compiler receives an absolute
input path because it resolved the relative path against another project.

Validation after the change:

- `bash scripts/build-app.sh debug`: passed, including icon compilation.
- `xcrun vtool -show-build dist/Minutes.app/Contents/MacOS/Minutes`:
  `minos 15.0`, `sdk 27.0`.
- `codesign --verify --deep --strict dist/Minutes.app`: passed.
- `bash -n scripts/build-app.sh` and `git diff --check`: passed.

The initial comparison used `/Applications/Nix Apps/Minutes.app`. Subsequent
UI checks ran the local debug bundle with SDK 27.0 metadata. Release packaging
is checked separately when updating the Nix package.
