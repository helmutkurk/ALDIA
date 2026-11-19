#!/usr/bin/env python3
"""Reject development URLs in distributable builds; never query an endpoint."""
import os
from urllib.parse import urlsplit

for name in ("API_BASE_URL", "PUBLIC_PORTAL_URL"):
    value = os.environ.get(name, "")
    try:
        url = urlsplit(value)
        url.port  # Validate malformed/out-of-range ports without a network call.
    except ValueError:
        raise SystemExit(f"::error::{name} is not a valid URL.") from None
    if (url.scheme != "https" or not url.hostname or url.username or url.password
            or url.query or url.fragment or url.hostname in ("localhost", "127.0.0.1", "::1")
            or any(character.isspace() for character in value)
            or url.hostname.endswith((".invalid", ".example"))
            or any(marker in value.upper() for marker in ("REPLACE", "YOUR-DOMAIN", "<", ">"))):
        raise SystemExit(f"::error::{name} must be a real HTTPS URL without credentials, query or fragment.")
    if name == "API_BASE_URL" and not url.path.rstrip("/").endswith("/api"):
        raise SystemExit("::error::API_BASE_URL must end in /api.")
