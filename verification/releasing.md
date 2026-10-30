# Releasing Minutes

Keep release instructions here rather than expanding the README.

## One-time setup

The Minutes repository's Actions secrets need `APP_STORE_CONNECT_KEY_P8` (raw
Apple .p8 contents), `APP_STORE_CONNECT_KEY_ID`, and `APP_STORE_CONNECT_ISSUER_ID`.
Configure them through GitHub settings; never commit or paste their values into logs.
The matching Developer ID signing identity and Minutes Sparkle key stay in the local
Keychain. The permanent workflow is `.github/workflows/notarize.yml`.

## Release

1. Update `Resources/Info.plist` with a new version and increasing build number.
   Run `bash scripts/swift-local.sh test --no-parallel`,
   `python3 scripts/test-configure-updates.py`, and commit/push the candidate.
2. Build with `MINUTES_RELEASE_BUILD=1 MINUTES_ENABLE_UPDATES=1`,
   `MINUTES_VERSION`, `MINUTES_BUILD_NUMBER`, and `MINUTES_SIGN_IDENTITY` set,
   using `bash scripts/build-app.sh release`. Signed microphone and calendar
   capabilities are checked automatically.
3. Package `dist/Minutes.app` with `ditto -c -k --sequesterRsrc --keepParent` as
   `Minutes-submit.zip`. Create a draft GitHub release at the candidate commit,
   upload this input asset, and calculate its SHA-256.
4. Dispatch **Notarize Minutes** with `tag`, `build`, and `sha256`. It only accepts
   matching signed Minutes archives from draft releases. It returns Apple's receipt
   and a stapled ZIP as an Actions artifact; it does not publish a release.
5. Download the artifact. Require an Accepted receipt, validate stapling, strict
   code signature, Gatekeeper, version/build, architecture, and entitlements.
6. Add concise HTML release notes in `release-notes/VERSION.html`. Put the final ZIP
   in `dist/releases/vVERSION/` and run `bash scripts/generate-appcast.sh VERSION`.
   This requires notes, embeds them in the signed feed, and verifies its signature.
   Verify the archive signature too. Never edit the signed feed after generation.
7. Replace the draft input asset with the final ZIP and `appcast.xml`, add release
   notes, then publish as latest. Download both public assets and compare hashes;
   verify the latest/download feed resolves to the new build. Record the commit,
   notarization receipt and asset hashes in `verification/release-VERSION.md`.

For local notarization with an existing Keychain profile, `scripts/release.sh`
remains available. Do not mix its output with a remote workflow's output.
