# Minutes 0.1.11 (build 12) — prepared, not published

The release candidate was built with Sparkle enabled and signed with
Developer ID Application: Tonk Labs LTD (8WVKS2F24C), hardened runtime,
secure timestamp, and microphone entitlement. Deep strict codesign verification
passed. Version/build and embedded Sparkle public key match source configuration.

The submission archive is dist/notarization-v0.1.11/Minutes-submit.zip.
No notarization credentials were found in the login keychain, environment, or
Minutes GitHub repository secrets. A notarytool profile is required to continue.
The app has not been notarized or stapled, and no release has been published.
Do not distribute this submission archive as the final release artifact.

The release signing check now requests verbose certificate output and captures
it before matching, avoiding the observed grep -q / pipefail SIGPIPE (141).
Remaining: notarize, staple, regenerate final ZIP and signed appcast, verify,
push the reviewed commits, tag v0.1.11, publish assets, verify remote digests/feed.
