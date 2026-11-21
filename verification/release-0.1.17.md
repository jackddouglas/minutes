# Minutes 0.1.17 (build 18)

Published 2026-11-21 at https://github.com/jackddouglas/minutes/releases/tag/v0.1.17.
The release tag points to e34d84fd07313a28c262074eff8c1be5f706656a.

- The serial Swift suite passed (87 app tests and 35 core tests reported, including six opt-in skips). All three release configuration tests passed.
- Apple accepted notarization request 7b9cb42c-9843-455b-98c3-b45e3276e479 in workflow run 44914914408.
- The stapled arm64 app passed strict code-signature verification, Gatekeeper, version/build checks, and signed microphone and calendar capability checks.
- Sparkle archive and feed signatures verified. The public archive, versioned feed, and latest download feed matched the locally verified files byte for byte.
- A Sparkle installation and relaunch from a previous release was not exercised. The live FaceTime test used the five-second automatic-stop prototype. Immediate automatic stop and the five-second reminder were covered by regression tests in the release candidate.

| Public asset | SHA-256 |
| --- | --- |
| Minutes-0.1.17-macos-arm64.zip | 8580523492cfb2af2f0189834897675b6a832b3c75b53255ad2dbf4a9127965a |
| appcast.xml | a310b219b0ae19ec230861b418a0315a1180341434f52d62be70b811b9598616 |
