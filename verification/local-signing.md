# Consistent local signing — 2026-10-29

Minutes previously hardcoded ad-hoc signing. Local builds now select the sole
Apple Development identity, or an explicit MINUTES_SIGN_IDENTITY override.
Ambiguous or missing identities fail before compilation; ad-hoc signing requires
an explicit override. No keychain items or permissions were modified.

## Validation

- bash -n scripts/build-app.sh and git diff --check passed.
- bash scripts/build-app.sh release passed.
- codesign --verify --deep --strict dist/Minutes.app passed outside the sandbox.
- Signed by Apple Development: jackdouglas2@me.com (4Z52FKZX53), team B4K52W3663.
- Requirement uses app.minutes.meetings and the signing certificate, not a cdhash.
- Two temporary executables with different code and hashes, signed with that
  identity and the same identifier, produced identical designated requirements.
  The second executable passed verification against the first requirement.
- The existing desktop-links-settings Tonk worktree already selects this identity
  by default. Its desktop/scripts/build-app.sh completed without the prior
  TONK_SIGN_IDENTITY=- override; deep strict signature verification passed.
- A sandboxed trust check returned CSSMERR_TP_NOT_TRUSTED; the identical check
  outside the sandbox passed with the full Apple certificate chain available.

## Scope and remaining runtime check

The Nix-managed installed Minutes app is a separate pinned-source build and was
not replaced. Use this checkout's dist/Minutes.app for the updated local build.
No live Keychain access flow was exercised. Existing items may need one final
approval when switching from the old ad-hoc identity. Future local builds should
use the same certificate; avoid MINUTES_SIGN_IDENTITY=- and TONK_SIGN_IDENTITY=-.
