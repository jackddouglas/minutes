# Calendar permission fix — 2026-10-30

The installed 0.1.11 Developer ID build returned denied when enabling Calendar
reminders despite the existing System Settings approval. Its signed entitlements
contained audio-input only. Hardened runtime also requires
`com.apple.security.personal-information.calendars`.

Added that entitlement to `Resources/Release.entitlements`. The release packaging
script now checks both privacy capabilities and their usage descriptions in the
signed app through `scripts/verify-release-permissions.py`.

- The guard rejected the old candidate for the missing Calendar entitlement.
- Rebuilt 0.1.12/build 13 passed the guard and deep strict code-signature verification.
- Live old installed app: toggling detection left it off with the access-denied message.
- Live corrected Developer ID build: detection switched on, Refresh Calendar became
  enabled, and the existing selected calendar yielded one upcoming Google Meet.
- No TCC resets or System Settings permission changes were made.

Reference: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.calendars
