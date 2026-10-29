# Sparkle updates — 2026-10-29

## Implemented

- Sparkle 2.10.0, pinned through SwiftPM; FluidAudio remains at 0.17.5.
- Check for Updates in the app and menu-bar menus for configured builds.
- HTTPS feed and 32-byte EdDSA public-key validation; Nix-managed copies disabled.
- Checks blocked while working; installation deferred until recording/transcription
  finishes. A selector assertion verifies the actual optional Sparkle callback.
- Framework and helpers embedded and signed inside out with the stable identity.
- Signed-feed requirement, archive verification before extraction, automatic checks,
  and user-confirmed installation for update-enabled builds.
- Minutes-specific private key created in Keychain account app.minutes.meetings;
  only the public key is stored in Resources/sparkle-public-key.txt.
- Release script requires a matching update key, Developer ID identity, and notary
  profile; it builds, notarizes, staples, validates, and generates the signed feed.
  It writes local artifacts only. Instructions are in README.md.

## Fresh evidence

- Focused updater tests passed, including deferred installation and the callback
  selector. An initial nearly-matching delegate method warning was corrected.
- Full Swift suite passed: 85 executed tests passed, 5 opt-in model/audio tests skipped.
- Three Python configuration tests passed.
- All three shell scripts passed individual bash -n checks; git diff --check passed.
- Update-enabled debug bundle built and passed deep strict codesign verification.
- generate_appcast generated a signed local test feed and archive. sign_update
  verified the feed; CryptoKit verified the archive Ed25519 signature against the
  public key extracted from the built application's Info.plist.
- Final ordinary release-configuration local build succeeded; deep strict codesign
  verification passed and its plist omits update configuration as intended.

## Remaining release validation

No release was published, no app was notarized in this task, and no installed app
was replaced. The running Nix copy was left alone. Menus and actual downloaded
update installation/relaunch have not been exercised in the live app. The public
feed will exist after appcast.xml and the archive are uploaded to the first
Sparkle-enabled GitHub release. Existing installations need that one-time upgrade.
The Nix package still builds pinned source and has not been migrated.

The earlier local-signing changes are preserved; all changes remain uncommitted.
