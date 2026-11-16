# Minutes 0.1.14 (build 15)

Published 2026-11-16: https://github.com/jackddouglas/minutes/releases/tag/v0.1.14

- Release source: `3bfa74a11c15b0e381339fdc3455c5af4b6676ed` (PR #4, menu bar
  recorder and library window, rebase-merged into main).
- Full serial suite passed: 81 app tests and 35 core tests, with six opt-in tests
  skipped. Three release configuration tests passed.
- Developer ID signed with Tonk Labs LTD (8WVKS2F24C), hardened runtime,
  secure timestamp, microphone and Calendar entitlements, and signed Sparkle updates.
- Notarization workflow run 43865045394. Attempt 1 failed with HTTP 403 (an
  expired Apple Developer agreement); attempt 2 succeeded after the agreement was
  signed, with the same draft archive and inputs:
  https://github.com/jackddouglas/minutes/actions/runs/43865045394
- Apple Accepted receipt: `a9260188-0bcb-47fc-9a70-9f7b4d11b447`.
- Downloaded workflow archive passed SHA-256, strict signature, staple, Gatekeeper
  (Notarized Developer ID), signed privacy-capability, version/build, and arm64
  architecture checks.
- Sparkle key in the Keychain matches the repository public key. Feed signature
  verified; it contains build 15, embedded release notes, and an EdDSA-signed
  enclosure whose length matches the archive.
- Published archive and feed, and the latest/download feed, downloaded again and
  matched local bytes exactly. Temporary submission asset removed.

| Artifact | SHA-256 |
| --- | --- |
| Minutes-0.1.14-macos-arm64.zip | `25847feced45c5189099ed484777adc022448572d7a350346f6ff666bf98e89f` |
| appcast.xml | `8b838b906b3cb3505886133659c246831f106e4e0a784946d702a443d22e5e27` |

Automatic update installation/relaunch from 0.1.13, a real Join and recording
from the menu bar recorder, and the transcript-ready notification were not
exercised. Installed /Applications and Nix-managed copies were not replaced.
