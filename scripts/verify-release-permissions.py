"""Verify privacy capabilities in the signed release, not just its source plist."""
import plistlib
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1])
result = subprocess.run(
    ["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(app)],
    capture_output=True, check=True,
)
entitlements = plistlib.loads(result.stdout)
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
for entitlement, usage in [
    ("com.apple.security.device.audio-input", "NSMicrophoneUsageDescription"),
    ("com.apple.security.personal-information.calendars", "NSCalendarsFullAccessUsageDescription"),
]:
    if entitlements.get(entitlement) is not True:
        raise SystemExit(f"Release is missing required entitlement: {entitlement}")
    if not str(info.get(usage, "")).strip():
        raise SystemExit(f"Release is missing required usage description: {usage}")
print("Signed microphone and calendar capabilities verified")
