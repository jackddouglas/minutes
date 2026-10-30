# Minutes 0.1.12 (build 13)

Published 2026-10-30: https://github.com/jackddouglas/minutes/releases/tag/v0.1.12

- Source and remote release tag: `f47c4e7d4b694e501f4cf9b72fc646bfa019c030`.
- Includes remembered audio sources/Meet browser, stereo capture and legacy
  transcription repair, Calendar hardened-runtime entitlement, and permanent
  Minutes notarization workflow. README remains limited to build and use.
- Full serial suite passed: 59 app tests and 35 core tests, with six opt-in tests
  skipped. Real recovery was verified separately. Three release configuration
  tests passed; workflow YAML and shell syntax passed validation.
- Developer ID signed with Tonk Labs LTD (8WVKS2F24C), hardened runtime,
  secure timestamp, microphone and Calendar entitlements, and signed Sparkle updates.
- Permanent workflow succeeded:
  https://github.com/jackddouglas/minutes/actions/runs/41048008263
- Apple Accepted receipt: `c1cf3c87-7b78-46ea-902e-99962fc11374`.
- Downloaded workflow bundle passed strict signature, staple, Gatekeeper,
  signed privacy-capability, version/build and arm64 architecture checks.
- Sparkle feed signature verified. CryptoKit independently verified the archive
  signature against the public key embedded in the app.
- Published ZIP and appcast were downloaded again and matched local bytes exactly.
  The latest/download appcast matches the new signed feed. GitHub asset digests
  match the hashes below. Temporary submission asset removed from the release.

| Artifact | SHA-256 |
| --- | --- |
| Minutes-0.1.12-macos-arm64.zip | `32cb1237735e198f8b79d4c199fa7d7412aa8e6573a21941a56dcd2e08c1a1f0` |
| appcast.xml | `26c9a303bbf49fd1b360503dcdc7fff64a8af342bda26a765834a5a600402c01` |

Calendar detection was verified live in the corrected Developer ID build, using
existing user consent and calendar selection. Live browser capture and automatic
update installation/relaunch were not exercised. Installed /Applications and
Nix-managed copies were not replaced as part of publication.

## Release notes feed correction

GitHub release notes were initially omitted from Sparkle's feed. Added versioned
HTML notes and a shared appcast-generation script that requires and embeds them
before signing. Local release packaging and remote-release instructions use it.
The 0.1.12 archive and enclosure signature are unchanged.

Corrected appcast SHA-256:
`991c9a34ddddcb9eee2a28c6362241e4beef9564f86fb80355aeba9c327f5022`.
GitHub asset digest, API download and fresh versioned download match. The signed
feed verifies and its embedded description matches the release-note source.
The latest/download URL initially continued serving the previous cached feed.
Live check found the installed app already on 0.1.12, so the update-offer layout
was not re-exercised. No app installation was performed during this correction.
