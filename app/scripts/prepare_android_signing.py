#!/usr/bin/env python3
"""Decode CI's keystore without printing credentials or touching the checkout."""
import base64
import binascii
import os
from pathlib import Path

required = (
    "ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD",
)
missing = [name for name in required if not os.environ.get(name)]
if missing:
    raise SystemExit(
        "::error::Android release needs GitHub Actions secrets: " + ", ".join(missing)
        + ". Helmut: follow documentation/mobile-release.md. Debug builds need none."
    )
try:
    keystore = base64.b64decode("".join(os.environ[required[0]].split()), validate=True)
except (ValueError, binascii.Error):
    raise SystemExit("::error::ANDROID_KEYSTORE_BASE64 is invalid base64.") from None
if not keystore:
    raise SystemExit("::error::ANDROID_KEYSTORE_BASE64 decoded to an empty keystore.")
path = Path(os.environ["RUNNER_TEMP"]) / "aldia-upload.jks"
path.write_bytes(keystore)
path.chmod(0o600)
