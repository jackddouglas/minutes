# Minutes 0.1.13 (build 14)

Published 2026-11-03: https://github.com/jackddouglas/minutes/releases/tag/v0.1.13

- Release source: `5a071dc9eac7f891b8659332665a7e04d9ada3d0`.
- Calendar recordings default to accepted attendees excluding the current user,
  rooms, and resources. Zero/missing accepted attendees retain Automatic; manual
  overrides and counts above 20 remain available.
- Full serial suite passed: 60 app tests and 35 core tests, with six opt-in tests
  skipped. Three release configuration tests passed. Diff whitespace checks passed.
  ContentView formatting diagnostics match the pre-existing baseline; other changed
  Swift files passed strict formatting checks.
- Developer ID signed with Tonk Labs LTD (8WVKS2F24C), hardened runtime,
  secure timestamp, microphone and Calendar entitlements, and signed Sparkle updates.
- Notarization workflow succeeded:
  https://github.com/jackddouglas/minutes/actions/runs/41620393904
- Apple Accepted receipt: `d693883a-5c81-4b81-b3c4-71a0d4226472`.
- Downloaded workflow archive passed strict signature, staple, Gatekeeper,
  signed privacy-capability, version/build, and arm64 architecture checks.
- Sparkle feed and archive signatures verified; embedded app public key matches
  the repository key. The feed contains versioned release notes and build 14.
- Published archive and feed downloaded again and matched local bytes exactly.
  The latest/download feed also matched. Temporary submission asset removed.

| Artifact | SHA-256 |
| --- | --- |
| Minutes-0.1.13-macos-arm64.zip | `423fcd6dc856bb4e890a69c27dbebd49f7942faa04bc55c34bfcda4a24d3729a` |
| appcast.xml | `dc03cf14ffd631c263cb820589507cb69e27aea6125c18a25a5473870c298eaf` |

Live Calendar recording and automatic update installation/relaunch were not
exercised. Installed /Applications and Nix-managed copies were not replaced.
