# Minutes 0.1.16 (build 17)

Published 2026-11-17: https://github.com/jackddouglas/minutes/releases/tag/v0.1.16

- Release source: `df2b378ede38dbc7dc0c426ca96d897e8552587c` (calendar speaker
  count kept while recording, calendar reminder withdrawn for the meeting being
  recorded, banner pinned to the top, recording pill in the recorder's red;
  committed directly to main).
- Full serial suite passed: 82 app tests and 35 core tests, with opt-in tests
  skipped. Three release configuration tests passed.
- Developer ID signed with Tonk Labs LTD (8WVKS2F24C), hardened runtime,
  secure timestamp, microphone and Calendar entitlements, and signed Sparkle updates.
- Notarization workflow run 44180418887 succeeded on the first attempt:
  https://github.com/jackddouglas/minutes/actions/runs/44180418887
- Apple Accepted receipt: `4edfe31a-a690-4204-9b3c-ebad36c6589b`.
- Submission archive SHA-256 `06c723e6e937065aeb0f866a927c0d1ea866ab4a26cd1f7f31c69363bdf46035`
  matched the draft asset digest.
- Downloaded workflow archive passed SHA-256, strict signature, staple, Gatekeeper
  (Notarized Developer ID), signed privacy-capability, version/build, and arm64
  architecture checks.
- Sparkle key in the Keychain matches the repository public key. Feed signature
  verified; it contains build 17, embedded release notes, and an EdDSA-signed
  enclosure whose length (15544453 bytes) matches the archive.
- Published archive and feed, and the latest/download feed, downloaded again and
  matched local bytes exactly. Temporary submission asset removed.

| Artifact | SHA-256 |
| --- | --- |
| Minutes-0.1.16-macos-arm64.zip | `dbd29062624edd630ab0d5ad3d8dd7fd9e4105f86c75d3c53a37be78dcc0e5a3` |
| appcast.xml | `9f4924d625dedeab6f0c59e8309c5f70f859e2c166f86e5bc74fd7700b7cf380` |

The speaker count, banner and pill colour were checked by tests and a local
build, not in the notarized build. A live calendar recording with this build and
automatic update installation from 0.1.15 were not exercised. Installed
/Applications and Nix-managed copies were not replaced.
