<p align="center">
  <img src="verification/icon/Default.png" width="180" alt="Minutes app icon">
</p>

<h1 align="center">Minutes</h1>

<p align="center">
  A native macOS app for recording meetings and transcribing them locally.
</p>

## Build

Requires macOS 15 or later, Apple Silicon, and full Xcode with Swift 6 and Icon Composer.

```sh
bash scripts/swift-local.sh test
bash scripts/build-app.sh release
open dist/Minutes.app
```

Local builds automatically use the sole Apple Development certificate in your keychain.
To choose another certificate, set `MINUTES_SIGN_IDENTITY` to its name or fingerprint
from `security find-identity -v -p codesigning`. Keep the same certificate across
rebuilds so saved Keychain access permissions remain valid. Switching from an old
ad-hoc build may require one final approval. `MINUTES_SIGN_IDENTITY=-` explicitly
opts into ad-hoc signing and may prompt again after each rebuild.

## Use

1. Pick an app under **System Audio** and press the record key, or import existing audio from the toolbar.
2. Press the same key again to stop and transcribe with speaker labels.
3. Click any word to listen, name speakers, and export Markdown.

Models download automatically on first use. Recordings and transcription stay on your Mac.

## Updates and releases

Sparkle 2 provides **Check for Updates…** in the application and menu-bar menus
for update-enabled builds. Automatic checks are enabled; installation requires
confirmation and waits until recording/transcription finishes. Ordinary local
builds and Nix-managed installations do not update themselves.

The public feed is `https://github.com/jackddouglas/minutes/releases/latest/download/appcast.xml`.
It becomes available when the first Sparkle-enabled release is published. Existing
0.1.10 installations need a one-time manual upgrade to that release.

The Minutes update-signing key is stored in the macOS Keychain under account
`app.minutes.meetings`. Only `Resources/sparkle-public-key.txt` is committed.
On the original signing Mac, `bash scripts/setup-updates.sh` is idempotent.
On another Mac, import the existing private key with Sparkle's `generate_keys`
tool before setup; do not generate a replacement key for an existing update feed.
Back up that private key securely outside the repository.

To inspect the updater in a development build:

```sh
MINUTES_ENABLE_UPDATES=1 bash scripts/build-app.sh debug
```

To prepare a release, use a Developer ID Application certificate and an existing
`notarytool` Keychain profile, then supply a new version and a strictly increasing
build number (0.1.10 used build 11):

```sh
MINUTES_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAM)' \
MINUTES_NOTARY_PROFILE='your-notary-profile' \
bash scripts/release.sh 0.1.11 12
```

This builds with hardened runtime and microphone entitlement, notarizes and
staples the app, and produces a ZIP plus signed `appcast.xml` under
`dist/releases/v0.1.11/`. It does not publish anything. Upload **both** files to the
matching GitHub release tag (`v0.1.11`), then mark it as the latest non-prerelease.
The archive URL in the feed points to that exact tag. Never edit the signed feed
after generating it. Run this on Apple Silicon; the archive is arm64.

The Nix package currently builds pinned source. To distribute this signed,
self-updating app, change that package to consume the release artifact and place
a writable copy outside the Nix store, or install the release app directly in
`/Applications`. Keeping it Nix-managed means continuing to update it through Nix.
