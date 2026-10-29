"""Validate release configuration and stamp the generated app, never source Info.plist."""
import base64
import os
from pathlib import Path
import plistlib
import re
import sys
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]

def configuration(env):
    feed = env.get("MINUTES_UPDATE_FEED_URL", "https://github.com/jackddouglas/minutes/releases/latest/download/appcast.xml")
    url = urlparse(feed)
    if url.scheme != "https" or not url.hostname or url.username or url.password:
        raise ValueError("MINUTES_UPDATE_FEED_URL must be an HTTPS URL without credentials")
    key = (ROOT / "Resources/sparkle-public-key.txt").read_text().strip()
    if len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("Invalid Sparkle public key; run scripts/setup-updates.sh")
    result = dict(SUFeedURL=feed, SUPublicEDKey=key, SURequireSignedFeed=True,
        SUVerifyUpdateBeforeExtraction=True, SUEnableAutomaticChecks=True,
        SUAllowsAutomaticUpdates=False)
    version, build = env.get("MINUTES_VERSION"), env.get("MINUTES_BUILD_NUMBER")
    if version is not None or build is not None or env.get("MINUTES_RELEASE_BUILD") == "1":
        if not version or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", version):
            raise ValueError("MINUTES_VERSION must be a numeric release version")
        if not build or not re.fullmatch(r"[1-9][0-9]*", build):
            raise ValueError("MINUTES_BUILD_NUMBER must be a positive integer increasing each release")
        result.update(CFBundleShortVersionString=version, CFBundleVersion=build)
    return result

if __name__ == "__main__":
    try:
        settings = configuration(os.environ)
        if sys.argv[1:] != ["--validate"]:
            path = Path(sys.argv[1])
            info = plistlib.loads(path.read_bytes())
            info.update(settings)
            path.write_bytes(plistlib.dumps(info))
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
