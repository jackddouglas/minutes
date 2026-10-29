# Minutes 0.1.10

Release scope: validated audio formats and multichannel routing, normalized PCM
channel extraction, a single alphabetical audio-source picker, and a sidebar
footer that blends into the background at rest and blurs scrolling content.

Version 0.1.10, build 11, based on merged PRs #1, #2, and #3.

Validation completed before publication:
- Full test suites passed with `bash scripts/swift-local.sh test --no-parallel`.
- Release bundle built with `bash scripts/build-app.sh release`.
- `codesign --verify --deep --strict` passed.
- Bundle version is 0.1.10, build 11; ZIP integrity check passed.
- Archive SHA-256: `1312cf19b898dbd31912d8b5b816b412ca3d4062ab7f268cef60919a92d79412`.

The footer was exercised in native light/dark split-view previews, including
scrolling and its bottom boundary. Live hardware capture was not re-tested for
this release; the older macOS footer fallback was not visually exercised.
The app is ad-hoc signed, not notarized.

Nix follow-up uses the release commit and a verified source hash. Preserve
unrelated staged dotfiles changes; package validation does not activate the
full system configuration.
