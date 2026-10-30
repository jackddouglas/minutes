# Minutes 0.1.11 (build 12)

## Verified release artifacts — 2026-10-30

- Built from source commit 7f94b431ccd00d1d442a29a66071351689651149, with
  Sparkle enabled, hardened runtime, secure timestamp, microphone entitlement,
  and Developer ID Application: Tonk Labs LTD (8WVKS2F24C).
- Apple notarization Accepted: 2e1e848f-2de7-470e-9035-c20f97fa306c.
- Used the existing Tonk App Store Connect API key entirely inside GitHub Actions:
  https://github.com/tonk-labs/tonk/actions/runs/41037759180
  The key was not exported. Temporary draft input and workflow branch are removed
  after publication; the receipt remains in dist/notarization-v0.1.11/receipt/.
- Stapling and staple validation passed; deep strict codesign verification passed.
- Gatekeeper assessment: accepted, source=Notarized Developer ID.
- Signed appcast verification passed. CryptoKit independently verified the archive
  signature against the public key embedded in the app.
- Appcast build 12 and versioned archive URL verified.

Final artifacts under dist/releases/v0.1.11/:

- Minutes-0.1.11-macos-arm64.zip SHA256:
  f5b147b66ad0b86ba2efc4e68eef94a0583b4583549932d33a199324ef13f602
- appcast.xml SHA256:
  fff3afdee211bd4b9ff604acd38349ca4179860eceeda8686b6a4cdfeefac556

The first read-only Actions token could not download the draft input; retry with
contents:write (required for private draft access) succeeded. No Tonk main-branch
code or credentials were changed.

Release destination: https://github.com/jackddouglas/minutes/releases/tag/v0.1.11
Live update installation/relaunch is not tested. Existing 0.1.10 installs require
one manual upgrade. The running Nix-managed installation remains unchanged.

## Published artifact verification

v0.1.11 was published as the latest stable release on 2026-10-30, with tag
pointing to e7ca077d87ebdedcabb41930b2abb3560e10b2d2. Both public assets were
downloaded again and matched the verified local bytes. The latest/download
appcast URL serves the expected signed feed. The downloaded app passed deep
strict signature verification, stapler validation, and Gatekeeper assessment
(source=Notarized Developer ID). The downloaded feed passed Sparkle verification.
The temporary Tonk draft release and workflow branch were deleted successfully.
