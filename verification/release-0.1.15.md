# Minutes 0.1.15 (build 16)

Published 2026-11-16: https://github.com/jackddouglas/minutes/releases/tag/v0.1.15

- Release source: `c80f9fd828b30ee3b1c4f23643ad538ff560a141` (inset meeting band
  on the menu bar recorder, committed directly to main).
- Full serial suite passed: 81 app tests and 35 core tests, with six opt-in tests
  skipped. Three release configuration tests passed.
- Developer ID signed with Tonk Labs LTD (8WVKS2F24C), hardened runtime,
  secure timestamp, microphone and Calendar entitlements, and signed Sparkle updates.
- Notarization workflow run 43894951211 succeeded on the first attempt:
  https://github.com/jackddouglas/minutes/actions/runs/43894951211
- Apple Accepted receipt: `787fe31e-4b5c-43ae-84c9-0b19c7faf67e`.
- Downloaded workflow archive passed SHA-256, strict signature, staple, Gatekeeper
  (Notarized Developer ID), signed privacy-capability, version/build, and arm64
  architecture checks.
- Sparkle key in the Keychain matches the repository public key. Feed signature
  verified; it contains build 16, embedded release notes, and an EdDSA-signed
  enclosure whose length (15543485 bytes) matches the archive.
- Published archive and feed, and the latest/download feed, downloaded again and
  matched local bytes exactly. Temporary submission asset removed.

| Artifact | SHA-256 |
| --- | --- |
| Minutes-0.1.15-macos-arm64.zip | `f808873e1b4ed704f411c9f8f1c40945fbc86d4e11fba3990d3f3983599ff459` |
| appcast.xml | `77ebe48157dcac3b3fd90bb25dc15d584214f51eae622b482f750b96eff9b759` |

The inset band was checked in rendered light and dark images and in a local
build, not in the notarized build. Automatic update installation/relaunch from
0.1.14 was not exercised. Installed /Applications and Nix-managed copies were
not replaced.
